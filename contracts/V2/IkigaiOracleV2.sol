// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract IkigaiOracleV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ORACLE_MANAGER = keccak256("ORACLE_MANAGER");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        address source;
        bool isActive;
    }

    struct OracleConfig {
        uint256 heartbeat;         // Maximum time between updates
        uint256 deviationThreshold; // Max price deviation allowed
        uint256 minimumSources;    // Minimum sources required
        uint256 validityDuration;  // How long prices remain valid
        bool requiresValidation;   // Whether validation is required
    }

    struct ValidationParams {
        uint256 maxDeviation;     // Maximum deviation between sources
        uint256 minConfidence;    // Minimum confidence score
        uint256 stalePriceAge;    // Maximum age for prices
        uint256 volatilityWindow; // Window for volatility calculation
    }

    // State variables
    mapping(address => mapping(address => PriceData)) public prices; // token => source => price
    mapping(address => OracleConfig) public configs;
    mapping(address => address[]) public priceSources;
    mapping(address => ValidationParams) public validationParams;
    
    // Events
    event PriceUpdated(
        address indexed token,
        address indexed source,
        uint256 price,
        uint256 confidence
    );
    event SourceAdded(address indexed token, address indexed source);
    event ConfigUpdated(address indexed token, string param, uint256 value);
    event ValidationFailed(address indexed token, string reason);
    event PriceValidated(address indexed token, uint256 price, uint256 confidence);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Core oracle functions
    function updatePrice(
        address token,
        uint256 price,
        uint256 confidence
    ) external onlyRole(UPDATER_ROLE) whenNotPaused {
        require(configs[token].heartbeat > 0, "Token not configured");
        
        PriceData storage data = prices[token][msg.sender];
        require(data.isActive, "Source not active");
        
        // Check heartbeat
        require(
            block.timestamp <= data.timestamp + configs[token].heartbeat,
            "Update too late"
        );
        
        // Check deviation
        if (data.price > 0) {
            uint256 deviation = calculateDeviation(data.price, price);
            require(
                deviation <= configs[token].deviationThreshold,
                "Deviation too high"
            );
        }
        
        // Update price data
        data.price = price;
        data.timestamp = block.timestamp;
        data.confidence = confidence;
        
        emit PriceUpdated(token, msg.sender, price, confidence);
        
        // Validate if required
        if (configs[token].requiresValidation) {
            validatePrice(token);
        }
    }

    function validatePrice(address token) public view returns (
        bool valid,
        uint256 validatedPrice,
        uint256 confidence
    ) {
        ValidationParams storage params = validationParams[token];
        address[] storage sources = priceSources[token];
        
        require(
            sources.length >= configs[token].minimumSources,
            "Insufficient sources"
        );
        
        uint256 totalPrice;
        uint256 totalConfidence;
        uint256 validSources;
        
        for (uint256 i = 0; i < sources.length; i++) {
            PriceData storage data = prices[token][sources[i]];
            
            // Check staleness
            if (block.timestamp > data.timestamp + params.stalePriceAge) {
                continue;
            }
            
            // Check confidence
            if (data.confidence < params.minConfidence) {
                continue;
            }
            
            totalPrice += data.price;
            totalConfidence += data.confidence;
            validSources++;
        }
        
        require(validSources >= configs[token].minimumSources, "Not enough valid sources");
        
        validatedPrice = totalPrice / validSources;
        confidence = totalConfidence / validSources;
        
        // Check max deviation between sources
        for (uint256 i = 0; i < sources.length; i++) {
            PriceData storage data = prices[token][sources[i]];
            uint256 deviation = calculateDeviation(data.price, validatedPrice);
            if (deviation > params.maxDeviation) {
                return (false, 0, 0);
            }
        }
        
        return (true, validatedPrice, confidence);
    }

    // Source management
    function addPriceSource(
        address token,
        address source,
        uint256 initialPrice,
        uint256 confidence
    ) external onlyRole(ORACLE_MANAGER) {
        require(!prices[token][source].isActive, "Source exists");
        
        prices[token][source] = PriceData({
            price: initialPrice,
            timestamp: block.timestamp,
            confidence: confidence,
            source: source,
            isActive: true
        });
        
        priceSources[token].push(source);
        
        emit SourceAdded(token, source);
    }

    // Configuration
    function configureToken(
        address token,
        uint256 heartbeat,
        uint256 deviationThreshold,
        uint256 minimumSources,
        uint256 validityDuration,
        bool requiresValidation
    ) external onlyRole(ORACLE_MANAGER) {
        configs[token] = OracleConfig({
            heartbeat: heartbeat,
            deviationThreshold: deviationThreshold,
            minimumSources: minimumSources,
            validityDuration: validityDuration,
            requiresValidation: requiresValidation
        });
        
        emit ConfigUpdated(token, "config", block.timestamp);
    }

    function setValidationParams(
        address token,
        uint256 maxDeviation,
        uint256 minConfidence,
        uint256 stalePriceAge,
        uint256 volatilityWindow
    ) external onlyRole(ORACLE_MANAGER) {
        validationParams[token] = ValidationParams({
            maxDeviation: maxDeviation,
            minConfidence: minConfidence,
            stalePriceAge: stalePriceAge,
            volatilityWindow: volatilityWindow
        });
        
        emit ConfigUpdated(token, "validation", block.timestamp);
    }

    // Helper functions
    function calculateDeviation(
        uint256 price1,
        uint256 price2
    ) public pure returns (uint256) {
        if (price1 > price2) {
            return ((price1 - price2) * 10000) / price1;
        }
        return ((price2 - price1) * 10000) / price2;
    }

    // View functions
    function getLatestPrice(
        address token
    ) external view returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence
    ) {
        (bool valid, uint256 validatedPrice, uint256 validatedConfidence) = validatePrice(token);
        require(valid, "Price validation failed");
        
        return (validatedPrice, block.timestamp, validatedConfidence);
    }

    function getPriceSources(
        address token
    ) external view returns (address[] memory) {
        return priceSources[token];
    }

    function getSourceData(
        address token,
        address source
    ) external view returns (PriceData memory) {
        return prices[token][source];
    }
} 