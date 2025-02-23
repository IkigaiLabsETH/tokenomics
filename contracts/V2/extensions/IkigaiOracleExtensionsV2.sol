// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";

contract IkigaiOracleExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ORACLE_MANAGER = keccak256("ORACLE_MANAGER");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    struct PriceFeed {
        address feed;            // Chainlink feed address
        uint256 heartbeat;       // Update frequency
        uint256 deviation;       // Price deviation threshold
        uint256 lastUpdate;      // Last update time
        bool isActive;           // Feed status
    }

    struct PriceData {
        uint256 price;          // Current price
        uint256 timestamp;      // Price timestamp
        uint256 confidence;     // Confidence score
        bytes32 source;         // Data source
        bool isValid;           // Validity status
    }

    struct ValidationConfig {
        uint256 minSources;     // Minimum sources required
        uint256 maxDeviation;   // Maximum deviation allowed
        uint256 staleAfter;     // Staleness threshold
        bool requiresVote;      // Vote requirement
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    
    mapping(address => PriceFeed) public priceFeeds;
    mapping(address => PriceData) public priceData;
    mapping(address => ValidationConfig) public validationConfigs;
    mapping(address => mapping(address => bool)) public trustedSources;
    
    uint256 public constant MAX_DEVIATION = 1000; // 10%
    uint256 public constant MIN_CONFIDENCE = 8000; // 80%
    uint256 public constant MAX_HEARTBEAT = 1 hours;
    
    // Events
    event FeedRegistered(address indexed token, address feed);
    event PriceUpdated(address indexed token, uint256 price);
    event ValidationFailed(address indexed token, string reason);
    event SourceTrusted(address indexed source, bool status);

    constructor(
        address _marketplace
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Feed management
    function registerPriceFeed(
        address token,
        address feed,
        uint256 heartbeat,
        uint256 deviation
    ) external onlyRole(ORACLE_MANAGER) {
        require(feed != address(0), "Invalid feed");
        require(heartbeat <= MAX_HEARTBEAT, "Heartbeat too long");
        require(deviation <= MAX_DEVIATION, "Deviation too high");
        
        priceFeeds[token] = PriceFeed({
            feed: feed,
            heartbeat: heartbeat,
            deviation: deviation,
            lastUpdate: block.timestamp,
            isActive: true
        });
        
        emit FeedRegistered(token, feed);
    }

    // Price updates
    function updatePrice(
        address token,
        uint256 price,
        bytes32 source
    ) external onlyRole(VALIDATOR_ROLE) {
        require(trustedSources[token][msg.sender], "Not trusted");
        
        ValidationConfig storage config = validationConfigs[token];
        require(
            _validatePrice(token, price),
            "Validation failed"
        );
        
        // Update price data
        priceData[token] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: _calculateConfidence(token, price),
            source: source,
            isValid: true
        });
        
        emit PriceUpdated(token, price);
    }

    // Price validation
    function validatePrices(
        address[] calldata tokens
    ) external onlyRole(VALIDATOR_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            PriceData storage data = priceData[tokens[i]];
            ValidationConfig storage config = validationConfigs[tokens[i]];
            
            // Check staleness
            if (block.timestamp - data.timestamp > config.staleAfter) {
                data.isValid = false;
                emit ValidationFailed(tokens[i], "Price stale");
                continue;
            }
            
            // Check confidence
            if (data.confidence < MIN_CONFIDENCE) {
                data.isValid = false;
                emit ValidationFailed(tokens[i], "Low confidence");
                continue;
            }
            
            // Validate against feed
            if (!_validateAgainstFeed(tokens[i])) {
                data.isValid = false;
                emit ValidationFailed(tokens[i], "Feed mismatch");
            }
        }
    }

    // Internal functions
    function _validatePrice(
        address token,
        uint256 price
    ) internal view returns (bool) {
        PriceData storage data = priceData[token];
        ValidationConfig storage config = validationConfigs[token];
        
        if (data.price > 0) {
            uint256 deviation = _calculateDeviation(data.price, price);
            if (deviation > config.maxDeviation) {
                return false;
            }
        }
        
        return true;
    }

    function _validateAgainstFeed(
        address token
    ) internal view returns (bool) {
        PriceFeed storage feed = priceFeeds[token];
        if (!feed.isActive) return true;
        
        AggregatorV3Interface chainlinkFeed = AggregatorV3Interface(feed.feed);
        (, int256 price,,,) = chainlinkFeed.latestRoundData();
        
        uint256 deviation = _calculateDeviation(
            uint256(price),
            priceData[token].price
        );
        
        return deviation <= feed.deviation;
    }

    function _calculateDeviation(
        uint256 price1,
        uint256 price2
    ) internal pure returns (uint256) {
        if (price1 > price2) {
            return ((price1 - price2) * 10000) / price1;
        } else {
            return ((price2 - price1) * 10000) / price2;
        }
    }

    function _calculateConfidence(
        address token,
        uint256 price
    ) internal view returns (uint256) {
        // Implementation needed
        return 10000;
    }

    // View functions
    function getPriceFeed(
        address token
    ) external view returns (PriceFeed memory) {
        return priceFeeds[token];
    }

    function getPriceData(
        address token
    ) external view returns (PriceData memory) {
        return priceData[token];
    }

    function getValidationConfig(
        address token
    ) external view returns (ValidationConfig memory) {
        return validationConfigs[token];
    }

    function isTrustedSource(
        address token,
        address source
    ) external view returns (bool) {
        return trustedSources[token][source];
    }
} 