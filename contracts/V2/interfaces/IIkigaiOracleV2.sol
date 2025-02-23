// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIkigaiOracleV2 {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        address source;
        bool isActive;
    }

    struct OracleConfig {
        uint256 heartbeat;
        uint256 deviationThreshold;
        uint256 minimumSources;
        uint256 validityDuration;
        bool requiresValidation;
    }

    struct ValidationParams {
        uint256 maxDeviation;
        uint256 minConfidence;
        uint256 stalePriceAge;
        uint256 volatilityWindow;
    }

    // View functions
    function getLatestPrice(address token) external view returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence
    );
    
    function validatePrice(address token) external view returns (
        bool valid,
        uint256 validatedPrice,
        uint256 confidence
    );
    
    function getPriceSources(address token) external view returns (address[] memory);
    function getSourceData(address token, address source) external view returns (PriceData memory);

    // State-changing functions
    function updatePrice(address token, uint256 price, uint256 confidence) external;
    function addPriceSource(address token, address source, uint256 initialPrice, uint256 confidence) external;
    function configureToken(
        address token,
        uint256 heartbeat,
        uint256 deviationThreshold,
        uint256 minimumSources,
        uint256 validityDuration,
        bool requiresValidation
    ) external;
    
    function setValidationParams(
        address token,
        uint256 maxDeviation,
        uint256 minConfidence,
        uint256 stalePriceAge,
        uint256 volatilityWindow
    ) external;

    // Events
    event PriceUpdated(address indexed token, address indexed source, uint256 price, uint256 confidence);
    event SourceAdded(address indexed token, address indexed source);
    event ConfigUpdated(address indexed token, string param, uint256 value);
    event ValidationFailed(address indexed token, string reason);
    event PriceValidated(address indexed token, uint256 price, uint256 confidence);
} 