// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";
import "../interfaces/IIkigaiFeeExtensionsV2.sol";

contract IkigaiMarketplaceExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MARKETPLACE_MANAGER = keccak256("MARKETPLACE_MANAGER");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct MarketConfig {
        uint256 minListingDuration;  // Minimum listing duration
        uint256 maxListingDuration;  // Maximum listing duration
        uint256 minBidIncrement;     // Minimum bid increment
        uint256 listingFee;          // Fee for listing (basis points)
        uint256 tradingFee;          // Fee for trading (basis points)
        bool requiresVerification;   // Whether verification is required
    }

    struct CollectionStats {
        uint256 totalVolume;         // Total trading volume
        uint256 floorPrice;          // Current floor price
        uint256 highestSale;         // Highest sale price
        uint256 activeListings;      // Number of active listings
        uint256 uniqueHolders;       // Number of unique holders
        uint256 lastUpdateTime;      // Last update timestamp
    }

    struct MarketActivity {
        uint256 timestamp;           // Activity timestamp
        ActivityType activityType;   // Type of activity
        address user;                // User address
        uint256 tokenId;            // Token ID
        uint256 price;              // Price involved
        bytes data;                 // Additional data
    }

    struct Listing {
        address seller;           // Seller address
        uint256 tokenId;         // NFT token ID
        uint256 price;           // Listing price
        uint256 startTime;       // Listing start time
        uint256 endTime;         // Listing end time
        bool isAuction;          // Whether listing is auction
        bool isActive;           // Whether listing is active
    }

    struct Auction {
        uint256 startPrice;      // Starting price
        uint256 reservePrice;    // Reserve price
        uint256 minBidIncrement; // Minimum bid increment
        uint256 highestBid;      // Current highest bid
        address highestBidder;   // Current highest bidder
        uint256 bidCount;        // Number of bids
        bool settled;            // Whether auction settled
    }

    struct Offer {
        address buyer;           // Offer maker
        uint256 price;           // Offer price
        uint256 expiry;         // Offer expiry time
        bool isActive;          // Whether offer is active
    }

    enum ActivityType {
        LIST,
        UNLIST,
        BID,
        SELL,
        TRANSFER,
        OFFER
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    IIkigaiFeeExtensionsV2 public feeExtension;
    
    mapping(address => MarketConfig) public marketConfigs;
    mapping(address => CollectionStats) public collectionStats;
    mapping(address => MarketActivity[]) public marketActivities;
    mapping(address => bool) public verifiedCollections;
    mapping(address => mapping(uint256 => Listing)) public listings;
    mapping(address => mapping(uint256 => Auction)) public auctions;
    mapping(address => mapping(uint256 => Offer[])) public offers;
    mapping(address => bool) public supportedCollections;
    
    uint256 public constant MAX_FEE = 1000; // 10%
    uint256 public constant MAX_LISTINGS = 100;
    uint256 public constant ACTIVITY_LIMIT = 1000;
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MAX_AUCTION_DURATION = 7 days;
    uint256 public constant MAX_OFFERS = 50;
    
    // Events
    event MarketConfigUpdated(address indexed collection, string parameter);
    event CollectionVerified(address indexed collection, bool status);
    event MarketActivityRecorded(address indexed collection, ActivityType activityType);
    event StatsUpdated(address indexed collection, uint256 floorPrice);
    event ListingCreated(address indexed collection, uint256 indexed tokenId, uint256 price);
    event ListingUpdated(address indexed collection, uint256 indexed tokenId, uint256 newPrice);
    event ListingCancelled(address indexed collection, uint256 indexed tokenId);
    event ListingSold(address indexed collection, uint256 indexed tokenId, address buyer, uint256 price);
    event AuctionBid(address indexed collection, uint256 indexed tokenId, address bidder, uint256 amount);
    event OfferCreated(address indexed collection, uint256 indexed tokenId, address buyer, uint256 price);
    event OfferAccepted(address indexed collection, uint256 indexed tokenId, address buyer, uint256 price);

    constructor(
        address _marketplace,
        address _oracle,
        address _feeExtension
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        feeExtension = IIkigaiFeeExtensionsV2(_feeExtension);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Market configuration
    function configureMarket(
        address collection,
        MarketConfig calldata config
    ) external onlyRole(MARKETPLACE_MANAGER) {
        require(collection != address(0), "Invalid collection");
        require(config.listingFee <= MAX_FEE, "Fee too high");
        require(config.tradingFee <= MAX_FEE, "Fee too high");
        
        marketConfigs[collection] = config;
        emit MarketConfigUpdated(collection, "config");
    }

    // Collection verification
    function verifyCollection(
        address collection,
        bool status
    ) external onlyRole(MARKETPLACE_MANAGER) {
        require(collection != address(0), "Invalid collection");
        verifiedCollections[collection] = status;
        emit CollectionVerified(collection, status);
    }

    // Market activity recording
    function recordMarketActivity(
        address collection,
        ActivityType activityType,
        address user,
        uint256 tokenId,
        uint256 price,
        bytes calldata data
    ) external onlyRole(OPERATOR_ROLE) {
        require(collection != address(0), "Invalid collection");
        
        MarketActivity[] storage activities = marketActivities[collection];
        require(activities.length < ACTIVITY_LIMIT, "Too many activities");
        
        activities.push(MarketActivity({
            timestamp: block.timestamp,
            activityType: activityType,
            user: user,
            tokenId: tokenId,
            price: price,
            data: data
        }));
        
        // Update collection stats based on activity
        _updateCollectionStats(collection, activityType, price);
        
        emit MarketActivityRecorded(collection, activityType);
    }

    // Stats management
    function updateCollectionStats(
        address collection
    ) external onlyRole(OPERATOR_ROLE) {
        CollectionStats storage stats = collectionStats[collection];
        require(
            block.timestamp >= stats.lastUpdateTime + 1 hours,
            "Too frequent"
        );
        
        // Get market data
        (uint256 floor, uint256 volume) = _getMarketData(collection);
        
        // Update stats
        stats.floorPrice = floor;
        stats.totalVolume += volume;
        stats.activeListings = _getActiveListings(collection);
        stats.uniqueHolders = _getUniqueHolders(collection);
        stats.lastUpdateTime = block.timestamp;
        
        emit StatsUpdated(collection, floor);
    }

    // Collection management
    function addCollection(
        address collection
    ) external onlyRole(MARKETPLACE_MANAGER) {
        require(!supportedCollections[collection], "Already supported");
        supportedCollections[collection] = true;
    }

    // Listing management
    function createListing(
        address collection,
        uint256 tokenId,
        uint256 price,
        bool isAuction,
        uint256 duration
    ) external nonReentrant whenNotPaused {
        require(supportedCollections[collection], "Collection not supported");
        require(price > 0, "Invalid price");
        
        if (isAuction) {
            require(
                duration >= MIN_AUCTION_DURATION &&
                duration <= MAX_AUCTION_DURATION,
                "Invalid duration"
            );
        }
        
        // Transfer NFT to contract
        IERC721(collection).transferFrom(msg.sender, address(this), tokenId);
        
        // Create listing
        listings[collection][tokenId] = Listing({
            seller: msg.sender,
            tokenId: tokenId,
            price: price,
            startTime: block.timestamp,
            endTime: isAuction ? block.timestamp + duration : 0,
            isAuction: isAuction,
            isActive: true
        });
        
        if (isAuction) {
            auctions[collection][tokenId] = Auction({
                startPrice: price,
                reservePrice: price,
                minBidIncrement: price / 20, // 5% increment
                highestBid: 0,
                highestBidder: address(0),
                bidCount: 0,
                settled: false
            });
        }
        
        emit ListingCreated(collection, tokenId, price);
    }

    // Auction bidding
    function placeBid(
        address collection,
        uint256 tokenId
    ) external payable nonReentrant {
        Listing storage listing = listings[collection][tokenId];
        Auction storage auction = auctions[collection][tokenId];
        
        require(listing.isActive && listing.isAuction, "Not active auction");
        require(block.timestamp <= listing.endTime, "Auction ended");
        require(
            msg.value >= auction.startPrice &&
            msg.value >= auction.highestBid + auction.minBidIncrement,
            "Bid too low"
        );
        
        // Refund previous bidder
        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }
        
        // Update auction
        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        auction.bidCount++;
        
        emit AuctionBid(collection, tokenId, msg.sender, msg.value);
    }

    // Offer management
    function makeOffer(
        address collection,
        uint256 tokenId,
        uint256 expiry
    ) external payable nonReentrant {
        require(supportedCollections[collection], "Collection not supported");
        require(msg.value > 0, "Invalid offer");
        require(expiry > block.timestamp, "Invalid expiry");
        
        Offer[] storage tokenOffers = offers[collection][tokenId];
        require(tokenOffers.length < MAX_OFFERS, "Too many offers");
        
        tokenOffers.push(Offer({
            buyer: msg.sender,
            price: msg.value,
            expiry: expiry,
            isActive: true
        }));
        
        emit OfferCreated(collection, tokenId, msg.sender, msg.value);
    }

    // Purchase handling
    function purchase(
        address collection,
        uint256 tokenId
    ) external payable nonReentrant {
        Listing storage listing = listings[collection][tokenId];
        require(listing.isActive && !listing.isAuction, "Invalid listing");
        require(msg.value >= listing.price, "Insufficient payment");
        
        // Handle fees
        uint256 fee = _calculateFee(msg.value);
        uint256 sellerAmount = msg.value - fee;
        
        // Transfer NFT to buyer
        IERC721(collection).transferFrom(address(this), msg.sender, tokenId);
        
        // Transfer payment to seller
        payable(listing.seller).transfer(sellerAmount);
        
        // Handle fee distribution
        if (fee > 0) {
            _handleFees(collection, fee);
        }
        
        // Update listing
        listing.isActive = false;
        
        emit ListingSold(collection, tokenId, msg.sender, msg.value);
    }

    // Internal functions
    function _updateCollectionStats(
        address collection,
        ActivityType activityType,
        uint256 price
    ) internal {
        CollectionStats storage stats = collectionStats[collection];
        
        if (activityType == ActivityType.SELL) {
            stats.totalVolume += price;
            if (price > stats.highestSale) {
                stats.highestSale = price;
            }
        } else if (activityType == ActivityType.LIST) {
            stats.activeListings++;
        } else if (activityType == ActivityType.UNLIST) {
            if (stats.activeListings > 0) {
                stats.activeListings--;
            }
        }
    }

    function _getMarketData(
        address collection
    ) internal view returns (uint256 floor, uint256 volume) {
        // Implementation needed - get data from marketplace/oracle
        return (0, 0);
    }

    function _getActiveListings(
        address collection
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _getUniqueHolders(
        address collection
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _calculateFee(
        uint256 amount
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _handleFees(
        address collection,
        uint256 fee
    ) internal {
        // Implementation needed
    }

    // View functions
    function getMarketConfig(
        address collection
    ) external view returns (MarketConfig memory) {
        return marketConfigs[collection];
    }

    function getCollectionStats(
        address collection
    ) external view returns (CollectionStats memory) {
        return collectionStats[collection];
    }

    function getMarketActivities(
        address collection,
        uint256 offset,
        uint256 limit
    ) external view returns (MarketActivity[] memory) {
        MarketActivity[] storage activities = marketActivities[collection];
        uint256 end = Math.min(offset + limit, activities.length);
        uint256 size = end - offset;
        
        MarketActivity[] memory result = new MarketActivity[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = activities[offset + i];
        }
        return result;
    }

    function isCollectionVerified(
        address collection
    ) external view returns (bool) {
        return verifiedCollections[collection];
    }

    function getListing(
        address collection,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return listings[collection][tokenId];
    }

    function getAuction(
        address collection,
        uint256 tokenId
    ) external view returns (Auction memory) {
        return auctions[collection][tokenId];
    }

    function getOffers(
        address collection,
        uint256 tokenId
    ) external view returns (Offer[] memory) {
        return offers[collection][tokenId];
    }

    function isCollectionSupported(
        address collection
    ) external view returns (bool) {
        return supportedCollections[collection];
    }
} 