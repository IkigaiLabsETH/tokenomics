// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiAuctionExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant AUCTION_MANAGER = keccak256("AUCTION_MANAGER");
    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");

    struct Auction {
        address seller;           // Seller address
        uint256 startPrice;      // Starting price
        uint256 reservePrice;    // Reserve price
        uint256 startTime;       // Start timestamp
        uint256 endTime;         // End timestamp
        bool isActive;           // Auction status
    }

    struct Bid {
        address bidder;          // Bidder address
        uint256 amount;          // Bid amount
        uint256 timestamp;       // Bid timestamp
        bool isValid;            // Bid validity
    }

    struct AuctionConfig {
        uint256 minDuration;     // Minimum auction duration
        uint256 maxDuration;     // Maximum auction duration
        uint256 minIncrement;    // Minimum bid increment
        uint256 extensionTime;   // Time extension on late bids
        bool requiresApproval;   // Whether approval required
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => Auction) public auctions;
    mapping(bytes32 => Bid[]) public auctionBids;
    mapping(bytes32 => AuctionConfig) public auctionConfigs;
    mapping(address => bool) public approvedBidders;
    
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MAX_AUCTION_DURATION = 7 days;
    uint256 public constant EXTENSION_THRESHOLD = 15 minutes;
    
    // Events
    event AuctionCreated(bytes32 indexed auctionId, uint256 startPrice);
    event BidPlaced(bytes32 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionSettled(bytes32 indexed auctionId, address winner, uint256 amount);
    event AuctionCancelled(bytes32 indexed auctionId, string reason);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Auction creation
    function createAuction(
        bytes32 auctionId,
        address collection,
        uint256 tokenId,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration
    ) external nonReentrant whenNotPaused {
        require(!auctions[auctionId].isActive, "Auction exists");
        require(startPrice > 0, "Invalid start price");
        require(duration >= MIN_AUCTION_DURATION, "Duration too short");
        require(duration <= MAX_AUCTION_DURATION, "Duration too long");
        
        // Transfer NFT to contract
        IERC721(collection).transferFrom(msg.sender, address(this), tokenId);
        
        // Create auction
        auctions[auctionId] = Auction({
            seller: msg.sender,
            startPrice: startPrice,
            reservePrice: reservePrice,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            isActive: true
        });
        
        emit AuctionCreated(auctionId, startPrice);
    }

    // Bidding
    function placeBid(
        bytes32 auctionId
    ) external payable nonReentrant {
        require(approvedBidders[msg.sender], "Not approved");
        
        Auction storage auction = auctions[auctionId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp >= auction.startTime, "Not started");
        require(block.timestamp < auction.endTime, "Ended");
        
        // Validate bid amount
        require(msg.value >= auction.startPrice, "Below start price");
        require(
            msg.value >= _getMinNextBid(auctionId),
            "Bid too low"
        );
        
        // Add bid
        auctionBids[auctionId].push(Bid({
            bidder: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp,
            isValid: true
        }));
        
        // Check for time extension
        if (auction.endTime - block.timestamp < EXTENSION_THRESHOLD) {
            auction.endTime += EXTENSION_THRESHOLD;
        }
        
        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    // Auction settlement
    function settleAuction(
        bytes32 auctionId
    ) external onlyRole(SETTLER_ROLE) nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.isActive, "Not active");
        require(block.timestamp >= auction.endTime, "Not ended");
        
        // Get winning bid
        Bid memory winningBid = _getWinningBid(auctionId);
        require(
            winningBid.amount >= auction.reservePrice,
            "Reserve not met"
        );
        
        // Transfer NFT to winner
        // Implementation needed
        
        // Transfer funds to seller
        // Implementation needed
        
        // Update auction status
        auction.isActive = false;
        
        emit AuctionSettled(auctionId, winningBid.bidder, winningBid.amount);
    }

    // Internal functions
    function _getMinNextBid(
        bytes32 auctionId
    ) internal view returns (uint256) {
        Bid[] storage bids = auctionBids[auctionId];
        if (bids.length == 0) {
            return auctions[auctionId].startPrice;
        }
        
        AuctionConfig storage config = auctionConfigs[auctionId];
        uint256 lastBid = bids[bids.length - 1].amount;
        
        return lastBid + ((lastBid * config.minIncrement) / 10000);
    }

    function _getWinningBid(
        bytes32 auctionId
    ) internal view returns (Bid memory) {
        Bid[] storage bids = auctionBids[auctionId];
        require(bids.length > 0, "No bids");
        
        uint256 highestAmount = 0;
        uint256 winningIndex = 0;
        
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].isValid && bids[i].amount > highestAmount) {
                highestAmount = bids[i].amount;
                winningIndex = i;
            }
        }
        
        return bids[winningIndex];
    }

    // View functions
    function getAuction(
        bytes32 auctionId
    ) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    function getAuctionBids(
        bytes32 auctionId
    ) external view returns (Bid[] memory) {
        return auctionBids[auctionId];
    }

    function getAuctionConfig(
        bytes32 auctionId
    ) external view returns (AuctionConfig memory) {
        return auctionConfigs[auctionId];
    }

    function isBidderApproved(
        address bidder
    ) external view returns (bool) {
        return approvedBidders[bidder];
    }
} 