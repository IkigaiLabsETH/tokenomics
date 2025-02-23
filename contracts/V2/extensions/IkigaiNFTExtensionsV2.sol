// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiNFTExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant NFT_MANAGER = keccak256("NFT_MANAGER");
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    struct Collection {
        address nftContract;     // NFT contract address
        uint256 floorPrice;      // Floor price
        uint256 totalSupply;     // Total supply
        uint256 totalHolders;    // Total holders
        bool isVerified;         // Verification status
    }

    struct NFTMetadata {
        uint256 tokenId;         // Token ID
        uint256 rarity;          // Rarity score
        uint256 lastPrice;       // Last sale price
        uint256 lastSale;        // Last sale time
        bool isListed;           // Listing status
    }

    struct CollectionStats {
        uint256 volume24h;       // 24h volume
        uint256 sales24h;        // 24h sales
        uint256 avgPrice;        // Average price
        uint256 highestSale;     // Highest sale
        uint256 lastUpdate;      // Last update time
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(address => Collection) public collections;
    mapping(address => mapping(uint256 => NFTMetadata)) public nftMetadata;
    mapping(address => CollectionStats) public collectionStats;
    mapping(address => bool) public verifiedCollections;
    
    uint256 public constant MIN_FLOOR_PRICE = 0.01 ether;
    uint256 public constant MAX_RARITY_SCORE = 10000;
    uint256 public constant STATS_UPDATE_INTERVAL = 1 hours;
    
    // Events
    event CollectionAdded(address indexed collection, bool verified);
    event NFTMetadataUpdated(address indexed collection, uint256 indexed tokenId);
    event StatsUpdated(address indexed collection, uint256 timestamp);
    event CollectionVerified(address indexed collection, bool status);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Collection management
    function addCollection(
        address nftContract,
        bool verified
    ) external onlyRole(NFT_MANAGER) {
        require(nftContract != address(0), "Invalid address");
        require(!collections[nftContract].isVerified, "Already added");
        
        IERC721 nft = IERC721(nftContract);
        
        collections[nftContract] = Collection({
            nftContract: nftContract,
            floorPrice: 0,
            totalSupply: nft.totalSupply(),
            totalHolders: _calculateHolders(nftContract),
            isVerified: verified
        });
        
        verifiedCollections[nftContract] = verified;
        
        emit CollectionAdded(nftContract, verified);
    }

    // Metadata management
    function updateNFTMetadata(
        address collection,
        uint256 tokenId,
        uint256 rarity,
        uint256 price
    ) external onlyRole(CURATOR_ROLE) {
        require(collections[collection].isVerified, "Not verified");
        require(rarity <= MAX_RARITY_SCORE, "Invalid rarity");
        
        NFTMetadata storage metadata = nftMetadata[collection][tokenId];
        metadata.tokenId = tokenId;
        metadata.rarity = rarity;
        
        if (price > 0) {
            metadata.lastPrice = price;
            metadata.lastSale = block.timestamp;
        }
        
        emit NFTMetadataUpdated(collection, tokenId);
    }

    // Stats management
    function updateCollectionStats(
        address collection,
        uint256 volume,
        uint256 sales,
        uint256 price
    ) external onlyRole(CURATOR_ROLE) {
        CollectionStats storage stats = collectionStats[collection];
        require(
            block.timestamp >= stats.lastUpdate + STATS_UPDATE_INTERVAL,
            "Too frequent"
        );
        
        // Update stats
        stats.volume24h = volume;
        stats.sales24h = sales;
        stats.avgPrice = _calculateAvgPrice(stats.avgPrice, price, sales);
        stats.highestSale = price > stats.highestSale ? price : stats.highestSale;
        stats.lastUpdate = block.timestamp;
        
        // Update floor price if needed
        if (price < collections[collection].floorPrice) {
            collections[collection].floorPrice = price;
        }
        
        emit StatsUpdated(collection, block.timestamp);
    }

    // Internal functions
    function _calculateHolders(
        address collection
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _calculateAvgPrice(
        uint256 currentAvg,
        uint256 newPrice,
        uint256 totalSales
    ) internal pure returns (uint256) {
        if (totalSales == 0) return newPrice;
        return (currentAvg * (totalSales - 1) + newPrice) / totalSales;
    }

    function _validateNFT(
        address collection,
        uint256 tokenId
    ) internal view returns (bool) {
        IERC721 nft = IERC721(collection);
        try nft.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }

    // View functions
    function getCollection(
        address collection
    ) external view returns (Collection memory) {
        return collections[collection];
    }

    function getNFTMetadata(
        address collection,
        uint256 tokenId
    ) external view returns (NFTMetadata memory) {
        return nftMetadata[collection][tokenId];
    }

    function getCollectionStats(
        address collection
    ) external view returns (CollectionStats memory) {
        return collectionStats[collection];
    }

    function isCollectionVerified(
        address collection
    ) external view returns (bool) {
        return verifiedCollections[collection];
    }
} 