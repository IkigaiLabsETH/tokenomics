// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

/// @title IkigaiMarketplace - Handles NFT marketplace operations and reward distribution
contract IkigaiMarketplace is Initializable, OwnableUpgradeable, ReentrancyGuard, Pausable {
    // --- Structs ---
    struct Listing {
        address seller;
        uint256 price;
        bool active;
        bool isAuction;
        uint256 endTime;
        uint256 highestBid;
        address highestBidder;
        uint256 royaltyPercentage;
        address creator;
    }

    struct MarketConfig {
        uint256 baseFee;        // Base marketplace fee (basis points)
        uint256 creatorFee;     // Creator royalty fee (basis points)
        uint256 minPrice;       // Minimum listing price
        uint256 maxRoyalty;     // Maximum royalty percentage
        uint256 auctionMinDuration; // Minimum auction duration
        uint256 auctionMaxDuration; // Maximum auction duration
    }

    struct Offer {
        address bidder;
        uint256 amount;
        uint256 expiry;
    }

    // --- Constants ---
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MIN_BID_INCREMENT = 100; // 1%
    uint256 private constant MAX_PRICE = 1_000_000 * 1e18; // 1M BERA max price
    uint256 private constant MAX_BATCH_SIZE = 20;
    uint256 private constant MIN_AUCTION_DURATION = 1 days;
    uint256 private constant MAX_AUCTION_DURATION = 30 days;

    // --- State Variables ---
    IERC20 public BERA;
    IERC721 public ikigaiNFT;
    address public treasury;
    
    MarketConfig public marketConfig;
    mapping(uint256 => Listing) public listings;
    mapping(address => uint256) public pendingReturns; // For auction refunds
    mapping(uint256 => Offer[]) public offersForToken;
    mapping(uint256 => mapping(address => bool)) public hasUserMadeOffer;
    uint256 public constant MAX_OFFERS_PER_TOKEN = 10;
    uint256 public constant MIN_OFFER_DURATION = 1 hours;
    uint256 public constant MAX_OFFER_DURATION = 7 days;

    // Add rate limiting
    mapping(address => uint256) public lastActionTime;
    uint256 private constant ACTION_COOLDOWN = 1 minutes;

    // Add emergency controls
    bool public emergencyMode;
    mapping(address => bool) public blacklisted;

    // --- Events ---
    event NFTListed(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price,
        bool isAuction,
        uint256 endTime
    );
    event NFTSold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );
    event AuctionBid(
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 amount
    );
    event AuctionSettled(
        uint256 indexed tokenId,
        address indexed winner,
        uint256 amount
    );
    event RoyaltyPaid(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 amount
    );
    event FeesDistributed(
        uint256 marketplaceFee,
        uint256 creatorFee,
        uint256 sellerAmount
    );
    event OfferPlaced(uint256 indexed tokenId, address indexed bidder, uint256 amount, uint256 expiry);
    event OfferAccepted(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event OfferCancelled(uint256 indexed tokenId, address indexed bidder);
    event BatchListed(uint256[] tokenIds, uint256[] prices);
    event EmergencyModeEnabled();
    event EmergencyModeDisabled();
    event BlacklistUpdated(address account, bool status);
    event EmergencyNFTWithdrawn(uint256 tokenId, address recipient);

    /// @notice Initialize the marketplace
    function initialize(
        address _bera,
        address _ikigaiNFT,
        address _treasury
    ) public initializer {
        __Ownable_init();
        
        BERA = IERC20(_bera);
        ikigaiNFT = IERC721(_ikigaiNFT);
        treasury = _treasury;

        marketConfig = MarketConfig({
            baseFee: 250,      // 2.5%
            creatorFee: 500,   // 5%
            minPrice: 100 * 1e18, // 100 BERA
            maxRoyalty: 1000,  // 10%
            auctionMinDuration: 1 days,
            auctionMaxDuration: 7 days
        });
    }

    // --- Listing Functions ---

    /// @notice List NFT for sale or auction
    function listNFT(
        uint256 tokenId,
        uint256 price,
        bool isAuction,
        uint256 duration,
        uint256 royaltyPercentage
    ) external 
        nonReentrant 
        whenNotPaused 
        notBlacklisted(msg.sender)
        validPrice(price)
        validRoyalty(royaltyPercentage) 
    {
        require(block.timestamp >= lastActionTime[msg.sender] + ACTION_COOLDOWN, "Too frequent");
        require(!emergencyMode, "System paused");
        
        // Validate auction duration
        if (isAuction) {
            require(
                duration >= MIN_AUCTION_DURATION && 
                duration <= MAX_AUCTION_DURATION,
                "Invalid duration"
            );
        }

        // Safe transfer check
        require(
            ikigaiNFT.ownerOf(tokenId) == msg.sender &&
            ikigaiNFT.getApproved(tokenId) == address(this),
            "Not authorized"
        );

        // Create listing with safety checks
        listings[tokenId] = Listing({
            seller: msg.sender,
            price: price,
            active: true,
            isAuction: isAuction,
            endTime: isAuction ? block.timestamp + duration : 0,
            highestBid: 0,
            highestBidder: address(0),
            royaltyPercentage: royaltyPercentage,
            creator: msg.sender
        });

        // Update rate limit
        lastActionTime[msg.sender] = block.timestamp;

        // Safe transfer
        try ikigaiNFT.transferFrom(msg.sender, address(this), tokenId) {
            emit NFTListed(tokenId, msg.sender, price, isAuction, block.timestamp + duration);
        } catch {
            revert("Transfer failed");
        }
    }

    /// @notice Buy listed NFT
    function buyNFT(uint256 tokenId) external 
        nonReentrant 
        whenNotPaused
        notBlacklisted(msg.sender) 
    {
        require(block.timestamp >= lastActionTime[msg.sender] + ACTION_COOLDOWN, "Too frequent");
        require(!emergencyMode, "System paused");
        
        Listing storage listing = listings[tokenId];
        require(listing.active && !listing.isAuction, "Not for sale");
        require(listing.seller != msg.sender, "Cannot buy own listing");
        
        uint256 price = listing.price;
        address seller = listing.seller;
        
        // Calculate fees with safe math
        uint256 marketplaceFee = (price * marketConfig.baseFee) / BASIS_POINTS;
        uint256 creatorFee = (price * listing.royaltyPercentage) / BASIS_POINTS;
        uint256 sellerAmount = price - marketplaceFee - creatorFee;
        
        // Require full amount
        require(
            BERA.balanceOf(msg.sender) >= price &&
            BERA.allowance(msg.sender, address(this)) >= price,
            "Insufficient funds/allowance"
        );
        
        // Update state before transfers
        listing.active = false;
        lastActionTime[msg.sender] = block.timestamp;
        
        // Execute transfers with checks
        require(BERA.transferFrom(msg.sender, treasury, marketplaceFee), "Fee transfer failed");
        require(BERA.transferFrom(msg.sender, seller, sellerAmount), "Seller transfer failed");
        
        if (creatorFee > 0) {
            require(BERA.transferFrom(msg.sender, listing.creator, creatorFee), "Creator fee failed");
            emit RoyaltyPaid(tokenId, listing.creator, creatorFee);
        }
        
        // Safe NFT transfer
        try ikigaiNFT.transferFrom(address(this), msg.sender, tokenId) {
            emit NFTSold(tokenId, seller, msg.sender, price);
            emit FeesDistributed(marketplaceFee, creatorFee, sellerAmount);
        } catch {
            revert("NFT transfer failed");
        }
    }

    // --- Auction Functions ---

    /// @notice Place bid on auction
    function placeBid(uint256 tokenId) external payable nonReentrant whenNotPaused {
        Listing storage listing = listings[tokenId];
        require(listing.active && listing.isAuction, "Not an active auction");
        require(block.timestamp < listing.endTime, "Auction ended");
        require(
            msg.value >= listing.price && 
            msg.value >= listing.highestBid + (listing.highestBid * MIN_BID_INCREMENT) / BASIS_POINTS,
            "Bid too low"
        );
        
        // Return previous bid
        if (listing.highestBidder != address(0)) {
            pendingReturns[listing.highestBidder] += listing.highestBid;
        }
        
        listing.highestBid = msg.value;
        listing.highestBidder = msg.sender;
        
        emit AuctionBid(tokenId, msg.sender, msg.value);
    }

    /// @notice Settle auction
    function settleAuction(uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[tokenId];
        require(listing.active && listing.isAuction, "Not an active auction");
        require(block.timestamp >= listing.endTime, "Auction not ended");
        
        address winner = listing.highestBidder;
        uint256 winningBid = listing.highestBid;
        
        // Calculate fees
        uint256 marketplaceFee = (winningBid * marketConfig.baseFee) / BASIS_POINTS;
        uint256 creatorFee = (winningBid * listing.royaltyPercentage) / BASIS_POINTS;
        uint256 sellerAmount = winningBid - marketplaceFee - creatorFee;
        
        // Execute transfers
        payable(treasury).transfer(marketplaceFee);
        payable(listing.seller).transfer(sellerAmount);
        
        if (creatorFee > 0) {
            payable(listing.creator).transfer(creatorFee);
            emit RoyaltyPaid(tokenId, listing.creator, creatorFee);
        }
        
        // Transfer NFT
        ikigaiNFT.transferFrom(address(this), winner, tokenId);
        listing.active = false;
        
        emit AuctionSettled(tokenId, winner, winningBid);
        emit FeesDistributed(marketplaceFee, creatorFee, sellerAmount);
    }

    /// @notice Withdraw pending returns from outbid
    function withdrawPendingReturns() external nonReentrant {
        uint256 amount = pendingReturns[msg.sender];
        if (amount > 0) {
            pendingReturns[msg.sender] = 0;
            payable(msg.sender).transfer(amount);
        }
    }

    // --- Offer Functions ---

    /// @notice Place an offer on a non-listed NFT
    function makeOffer(uint256 tokenId, uint256 duration) external payable nonReentrant whenNotPaused {
        require(!listings[tokenId].active, "Token already listed");
        require(duration >= MIN_OFFER_DURATION && duration <= MAX_OFFER_DURATION, "Invalid duration");
        require(msg.value >= marketConfig.minPrice, "Offer too low");
        require(!hasUserMadeOffer[tokenId][msg.sender], "Already made offer");
        
        Offer[] storage offers = offersForToken[tokenId];
        require(offers.length < MAX_OFFERS_PER_TOKEN, "Too many offers");

        offers.push(Offer({
            bidder: msg.sender,
            amount: msg.value,
            expiry: block.timestamp + duration
        }));
        hasUserMadeOffer[tokenId][msg.sender] = true;

        emit OfferPlaced(tokenId, msg.sender, msg.value, block.timestamp + duration);
    }

    /// @notice Accept an offer
    function acceptOffer(uint256 tokenId, uint256 offerIndex) external nonReentrant {
        require(ikigaiNFT.ownerOf(tokenId) == msg.sender, "Not owner");
        
        Offer[] storage offers = offersForToken[tokenId];
        require(offerIndex < offers.length, "Invalid offer index");
        
        Offer memory offer = offers[offerIndex];
        require(block.timestamp <= offer.expiry, "Offer expired");

        // Calculate fees
        uint256 marketplaceFee = (offer.amount * marketConfig.baseFee) / BASIS_POINTS;
        uint256 creatorFee = (offer.amount * marketConfig.creatorFee) / BASIS_POINTS;
        uint256 sellerAmount = offer.amount - marketplaceFee - creatorFee;

        // Execute transfers
        payable(treasury).transfer(marketplaceFee);
        payable(msg.sender).transfer(sellerAmount);
        if (creatorFee > 0) {
            payable(ikigaiNFT.ownerOf(tokenId)).transfer(creatorFee);
        }

        // Transfer NFT
        ikigaiNFT.transferFrom(msg.sender, offer.bidder, tokenId);
        
        // Clean up offers
        _removeOffer(tokenId, offerIndex);
        
        emit OfferAccepted(tokenId, offer.bidder, offer.amount);
    }

    /// @notice Batch list multiple NFTs
    function batchListNFT(
        uint256[] calldata tokenIds,
        uint256[] calldata prices,
        uint256[] calldata royaltyPercentages
    ) external nonReentrant whenNotPaused {
        require(
            tokenIds.length == prices.length && 
            tokenIds.length == royaltyPercentages.length,
            "Array length mismatch"
        );
        require(tokenIds.length <= MAX_BATCH_SIZE, "Batch too large");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(ikigaiNFT.ownerOf(tokenIds[i]) == msg.sender, "Not owner");
            require(prices[i] >= marketConfig.minPrice, "Price too low");
            require(royaltyPercentages[i] <= marketConfig.maxRoyalty, "Royalty too high");

            listings[tokenIds[i]] = Listing({
                seller: msg.sender,
                price: prices[i],
                active: true,
                isAuction: false,
                endTime: 0,
                highestBid: 0,
                highestBidder: address(0),
                royaltyPercentage: royaltyPercentages[i],
                creator: msg.sender
            });

            ikigaiNFT.transferFrom(msg.sender, address(this), tokenIds[i]);
        }

        emit BatchListed(tokenIds, prices);
    }

    /// @notice Internal function to remove an offer
    function _removeOffer(uint256 tokenId, uint256 offerIndex) internal {
        Offer[] storage offers = offersForToken[tokenId];
        hasUserMadeOffer[tokenId][offers[offerIndex].bidder] = false;
        
        // Move last offer to removed position and pop
        if (offerIndex < offers.length - 1) {
            offers[offerIndex] = offers[offers.length - 1];
        }
        offers.pop();
    }

    /// @notice Cancel an expired offer
    function cancelExpiredOffer(uint256 tokenId, uint256 offerIndex) external nonReentrant {
        Offer[] storage offers = offersForToken[tokenId];
        require(offerIndex < offers.length, "Invalid offer index");
        require(block.timestamp > offers[offerIndex].expiry, "Not expired");

        address bidder = offers[offerIndex].bidder;
        uint256 amount = offers[offerIndex].amount;

        _removeOffer(tokenId, offerIndex);
        payable(bidder).transfer(amount);

        emit OfferCancelled(tokenId, bidder);
    }

    // --- Admin Functions ---

    /// @notice Update marketplace configuration
    function updateMarketConfig(
        uint256 _baseFee,
        uint256 _creatorFee,
        uint256 _minPrice,
        uint256 _maxRoyalty,
        uint256 _minDuration,
        uint256 _maxDuration
    ) external onlyOwner {
        require(_baseFee + _creatorFee <= 2000, "Total fees too high"); // Max 20%
        
        marketConfig.baseFee = _baseFee;
        marketConfig.creatorFee = _creatorFee;
        marketConfig.minPrice = _minPrice;
        marketConfig.maxRoyalty = _maxRoyalty;
        marketConfig.auctionMinDuration = _minDuration;
        marketConfig.auctionMaxDuration = _maxDuration;
    }

    /// @notice Enable emergency mode
    function enableEmergencyMode() external onlyOwner {
        emergencyMode = true;
        emit EmergencyModeEnabled();
    }

    /// @notice Disable emergency mode
    function disableEmergencyMode() external onlyOwner {
        emergencyMode = false;
        emit EmergencyModeDisabled();
    }

    /// @notice Update blacklist status
    function updateBlacklist(address account, bool status) external onlyOwner {
        blacklisted[account] = status;
        emit BlacklistUpdated(account, status);
    }

    /// @notice Emergency withdraw NFT
    function emergencyWithdrawNFT(
        uint256 tokenId,
        address recipient
    ) external onlyOwner {
        require(emergencyMode, "Not in emergency");
        require(recipient != address(0), "Invalid recipient");
        
        Listing storage listing = listings[tokenId];
        if (listing.active) {
            listing.active = false;
            if (listing.isAuction && listing.highestBid > 0) {
                pendingReturns[listing.highestBidder] += listing.highestBid;
            }
        }
        
        ikigaiNFT.transferFrom(address(this), recipient, tokenId);
        emit EmergencyNFTWithdrawn(tokenId, recipient);
    }

    /// @notice Pause marketplace
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause marketplace
    function unpause() external onlyOwner {
        _unpause();
    }

    // Add security-focused modifiers
    modifier validPrice(uint256 price) {
        require(price >= marketConfig.minPrice && price <= MAX_PRICE, "Invalid price");
        _;
    }

    modifier validRoyalty(uint256 royalty) {
        require(royalty <= marketConfig.maxRoyalty, "Royalty too high");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Account blacklisted");
        _;
    }
} 