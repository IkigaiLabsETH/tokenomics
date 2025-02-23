// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiTreasuryV2.sol";

contract IkigaiRoyaltyExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ROYALTY_MANAGER = keccak256("ROYALTY_MANAGER");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    struct RoyaltyConfig {
        uint256 rate;             // Royalty rate
        uint256 minAmount;        // Minimum royalty amount
        uint256 maxAmount;        // Maximum royalty amount
        address recipient;        // Royalty recipient
        bool isActive;            // Config status
    }

    struct RoyaltyStats {
        uint256 totalCollected;   // Total royalties collected
        uint256 totalDistributed; // Total royalties distributed
        uint256 lastCollection;   // Last collection time
        uint256 lastDistribution; // Last distribution time
        uint256 pendingAmount;    // Pending royalties
    }

    struct CollectionRoyalty {
        uint256 primaryRate;      // Primary sale rate
        uint256 secondaryRate;    // Secondary sale rate
        uint256 totalRoyalties;   // Total royalties
        address[] recipients;     // Royalty recipients
        uint256[] shares;         // Recipient shares
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiTreasuryV2 public treasury;
    
    mapping(address => RoyaltyConfig) public royaltyConfigs;
    mapping(address => RoyaltyStats) public royaltyStats;
    mapping(address => CollectionRoyalty) public collectionRoyalties;
    mapping(address => bool) public supportedCollections;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_ROYALTY_RATE = 2500; // 25%
    uint256 public constant MIN_DISTRIBUTION = 100; // Min distribution amount
    
    // Events
    event RoyaltyConfigured(address indexed collection, uint256 rate);
    event RoyaltyCollected(address indexed collection, uint256 amount);
    event RoyaltyDistributed(address indexed recipient, uint256 amount);
    event RecipientsUpdated(address indexed collection, address[] recipients);

    constructor(
        address _marketplace,
        address _treasury
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        treasury = IIkigaiTreasuryV2(_treasury);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Configuration management
    function configureRoyalty(
        address collection,
        RoyaltyConfig calldata config
    ) external onlyRole(ROYALTY_MANAGER) {
        require(config.rate <= MAX_ROYALTY_RATE, "Rate too high");
        require(config.recipient != address(0), "Invalid recipient");
        
        royaltyConfigs[collection] = config;
        supportedCollections[collection] = true;
        
        emit RoyaltyConfigured(collection, config.rate);
    }

    // Collection royalty setup
    function setupCollectionRoyalty(
        address collection,
        uint256 primaryRate,
        uint256 secondaryRate,
        address[] calldata recipients,
        uint256[] calldata shares
    ) external onlyRole(ROYALTY_MANAGER) {
        require(recipients.length == shares.length, "Length mismatch");
        require(primaryRate <= MAX_ROYALTY_RATE, "Primary rate too high");
        require(secondaryRate <= MAX_ROYALTY_RATE, "Secondary rate too high");
        
        uint256 totalShares;
        for (uint256 i = 0; i < shares.length; i++) {
            totalShares += shares[i];
        }
        require(totalShares == BASIS_POINTS, "Invalid shares");
        
        collectionRoyalties[collection] = CollectionRoyalty({
            primaryRate: primaryRate,
            secondaryRate: secondaryRate,
            totalRoyalties: 0,
            recipients: recipients,
            shares: shares
        });
        
        emit RecipientsUpdated(collection, recipients);
    }

    // Royalty collection
    function collectRoyalty(
        address collection,
        uint256 salePrice,
        bool isPrimarySale
    ) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant returns (uint256) {
        require(supportedCollections[collection], "Collection not supported");
        
        CollectionRoyalty storage royalty = collectionRoyalties[collection];
        uint256 rate = isPrimarySale ? royalty.primaryRate : royalty.secondaryRate;
        
        // Calculate royalty
        uint256 amount = (salePrice * rate) / BASIS_POINTS;
        if (amount == 0) return 0;
        
        // Update stats
        RoyaltyStats storage stats = royaltyStats[collection];
        stats.totalCollected += amount;
        stats.pendingAmount += amount;
        stats.lastCollection = block.timestamp;
        
        royalty.totalRoyalties += amount;
        
        emit RoyaltyCollected(collection, amount);
        return amount;
    }

    // Royalty distribution
    function distributeRoyalties(
        address collection
    ) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        RoyaltyStats storage stats = royaltyStats[collection];
        require(stats.pendingAmount >= MIN_DISTRIBUTION, "Amount too small");
        
        CollectionRoyalty storage royalty = collectionRoyalties[collection];
        uint256 amount = stats.pendingAmount;
        stats.pendingAmount = 0;
        
        // Distribute to recipients
        for (uint256 i = 0; i < royalty.recipients.length; i++) {
            uint256 share = (amount * royalty.shares[i]) / BASIS_POINTS;
            if (share > 0) {
                payable(royalty.recipients[i]).transfer(share);
                emit RoyaltyDistributed(royalty.recipients[i], share);
            }
        }
        
        stats.totalDistributed += amount;
        stats.lastDistribution = block.timestamp;
    }

    // Internal functions
    function _validateRoyaltyConfig(
        RoyaltyConfig memory config
    ) internal pure returns (bool) {
        return config.rate <= MAX_ROYALTY_RATE &&
               config.minAmount < config.maxAmount &&
               config.recipient != address(0);
    }

    function _calculateRoyaltyAmount(
        uint256 salePrice,
        uint256 rate
    ) internal pure returns (uint256) {
        return (salePrice * rate) / BASIS_POINTS;
    }

    // View functions
    function getRoyaltyConfig(
        address collection
    ) external view returns (RoyaltyConfig memory) {
        return royaltyConfigs[collection];
    }

    function getRoyaltyStats(
        address collection
    ) external view returns (RoyaltyStats memory) {
        return royaltyStats[collection];
    }

    function getCollectionRoyalty(
        address collection
    ) external view returns (CollectionRoyalty memory) {
        return collectionRoyalties[collection];
    }

    function isCollectionSupported(
        address collection
    ) external view returns (bool) {
        return supportedCollections[collection];
    }
} 