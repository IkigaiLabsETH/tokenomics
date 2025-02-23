// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IIkigaiOracleV2.sol";
import "./interfaces/IIkigaiVaultV2.sol";

contract IkigaiMarketplaceV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MARKETPLACE_MANAGER = keccak256("MARKETPLACE_MANAGER");
    bytes32 public constant FEE_MANAGER = keccak256("FEE_MANAGER");

    struct Listing {
        address seller;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        bool isAuction;
        uint256 minBid;
        uint256 highestBid;
        address highestBidder;
        bool isActive;
    }

    struct Collection {
        bool isSupported;
        uint256 royaltyFee;      // In basis points
        address royaltyReceiver;
        uint256 tradingVolume;
        uint256 floorPrice;
        uint256 lastTradeTime;
    }

    struct MarketStats {
        uint256 totalVolume;
        uint256 totalTrades;
        uint256 activeListings;
        uint256 totalCollections;
        uint256 uniqueTraders;
    }

    // State variables
    mapping(address => mapping(uint256 => Listing)) public listings; // collection => tokenId => listing
    mapping(address => Collection) public collections;
    mapping(address => bool) public paymentTokens;
    mapping(address => uint256) public userVolume;
    
    IIkigaiOracleV2 public oracle;
    IIkigaiVaultV2 public vault;
    MarketStats public stats;
    
    uint256 public platformFee; // In basis points
    uint256 public minListingDuration;
    uint256 public maxListingDuration;
    uint256 public minAuctionIncrement; // In basis points
    
    // Events
    event Listed(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price,
        bool isAuction
    );
    event Sale(
        address indexed collection,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );
    event BidPlaced(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 amount
    );
    event CollectionAdded(
        address indexed collection,
        uint256 royaltyFee,
        address royaltyReceiver
    );
    event ListingUpdated(
        address indexed collection,
        uint256 indexed tokenId,
        uint256 newPrice
    );

    constructor(
        address _oracle,
        address _vault,
        uint256 _platformFee
    ) {
        oracle = IIkigaiOracleV2(_oracle);
        vault = IIkigaiVaultV2(_vault);
        platformFee = _platformFee;
        
        minListingDuration = 1 hours;
        maxListingDuration = 30 days;
        minAuctionIncrement = 500; // 5%
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Core marketplace functions
    function listItem(
        address collection,
        uint256 tokenId,
        uint256 price,
        uint256 duration,
        bool isAuction,
        uint256 minBid
    ) external nonReentrant whenNotPaused {
        require(collections[collection].isSupported, "Collection not supported");
        require(duration >= minListingDuration, "Duration too short");
        require(duration <= maxListingDuration, "Duration too long");
        
        IERC721 nft = IERC721(collection);
        require(
            nft.ownerOf(tokenId) == msg.sender,
            "Not token owner"
        );
        
        // Transfer NFT to marketplace
        nft.transferFrom(msg.sender, address(this), tokenId);
        
        // Create listing
        listings[collection][tokenId] = Listing({
            seller: msg.sender,
            price: price,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            isAuction: isAuction,
            minBid: minBid,
            highestBid: 0,
            highestBidder: address(0),
            isActive: true
        });
        
        stats.activeListings++;
        
        emit Listed(collection, tokenId, msg.sender, price, isAuction);
    }

    function buyItem(
        address collection,
        uint256 tokenId,
        address paymentToken
    ) external nonReentrant whenNotPaused {
        require(paymentTokens[paymentToken], "Payment token not supported");
        
        Listing storage listing = listings[collection][tokenId];
        require(listing.isActive, "Listing not active");
        require(!listing.isAuction, "Item is in auction");
        require(block.timestamp <= listing.endTime, "Listing expired");
        
        IERC20 token = IERC20(paymentToken);
        uint256 price = listing.price;
        
        // Calculate fees
        uint256 platformAmount = (price * platformFee) / 10000;
        uint256 royaltyAmount = (price * collections[collection].royaltyFee) / 10000;
        uint256 sellerAmount = price - platformAmount - royaltyAmount;
        
        // Transfer payment
        require(
            token.transferFrom(msg.sender, address(vault), platformAmount),
            "Platform fee transfer failed"
        );
        
        if (royaltyAmount > 0) {
            require(
                token.transferFrom(
                    msg.sender,
                    collections[collection].royaltyReceiver,
                    royaltyAmount
                ),
                "Royalty transfer failed"
            );
        }
        
        require(
            token.transferFrom(msg.sender, listing.seller, sellerAmount),
            "Payment transfer failed"
        );
        
        // Transfer NFT
        IERC721(collection).transferFrom(address(this), msg.sender, tokenId);
        
        // Update stats
        stats.totalVolume += price;
        stats.totalTrades++;
        collections[collection].tradingVolume += price;
        collections[collection].lastTradeTime = block.timestamp;
        userVolume[msg.sender] += price;
        
        if (price < collections[collection].floorPrice || collections[collection].floorPrice == 0) {
            collections[collection].floorPrice = price;
        }
        
        delete listings[collection][tokenId];
        stats.activeListings--;
        
        emit Sale(collection, tokenId, listing.seller, msg.sender, price);
    }

    function placeBid(
        address collection,
        uint256 tokenId,
        uint256 bidAmount,
        address paymentToken
    ) external nonReentrant whenNotPaused {
        require(paymentTokens[paymentToken], "Payment token not supported");
        
        Listing storage listing = listings[collection][tokenId];
        require(listing.isActive && listing.isAuction, "Not active auction");
        require(block.timestamp <= listing.endTime, "Auction ended");
        require(bidAmount >= listing.minBid, "Bid too low");
        
        if (listing.highestBid > 0) {
            require(
                bidAmount >= listing.highestBid + 
                (listing.highestBid * minAuctionIncrement) / 10000,
                "Bid increment too low"
            );
            
            // Refund previous bidder
            IERC20(paymentToken).transfer(
                listing.highestBidder,
                listing.highestBid
            );
        }
        
        // Transfer bid amount to contract
        require(
            IERC20(paymentToken).transferFrom(
                msg.sender,
                address(this),
                bidAmount
            ),
            "Bid transfer failed"
        );
        
        listing.highestBid = bidAmount;
        listing.highestBidder = msg.sender;
        
        emit BidPlaced(collection, tokenId, msg.sender, bidAmount);
    }

    // Collection management
    function addCollection(
        address collection,
        uint256 royaltyFee,
        address royaltyReceiver
    ) external onlyRole(MARKETPLACE_MANAGER) {
        require(!collections[collection].isSupported, "Already supported");
        require(royaltyFee <= 1000, "Royalty too high"); // Max 10%
        
        collections[collection] = Collection({
            isSupported: true,
            royaltyFee: royaltyFee,
            royaltyReceiver: royaltyReceiver,
            tradingVolume: 0,
            floorPrice: 0,
            lastTradeTime: 0
        });
        
        stats.totalCollections++;
        
        emit CollectionAdded(collection, royaltyFee, royaltyReceiver);
    }

    // Fee management
    function updatePlatformFee(
        uint256 newFee
    ) external onlyRole(FEE_MANAGER) {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        platformFee = newFee;
    }

    // View functions
    function getListingInfo(
        address collection,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return listings[collection][tokenId];
    }

    function getCollectionStats(
        address collection
    ) external view returns (Collection memory) {
        return collections[collection];
    }

    function getMarketStats() external view returns (MarketStats memory) {
        return stats;
    }
} 