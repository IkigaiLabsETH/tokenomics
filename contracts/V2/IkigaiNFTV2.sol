// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IkigaiTokenV2.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract IkigaiNFTV2 is Initializable, ERC721Upgradeable, OwnableUpgradeable, ReentrancyGuard, Pausable {
    // Core dependencies
    IkigaiTokenV2 public immutable ikigaiToken;
    IERC20 public immutable BERA;
    
    // Enhanced series management
    struct Series {
        uint256 id;
        uint256 basePrice;
        uint256 maxSupply;
        uint256 currentSupply;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        uint256 minStakeRequired;
        uint256 stakeDuration;
        bool allowsStakingDiscount;
        bool allowsEcosystemDiscount;
        uint256 burnPercentage; // Percentage of price to burn (in basis points)
        mapping(address => bool) whitelist;
        bool whitelistOnly;
    }

    // Staking tiers with lower requirements
    struct StakingTier {
        uint256 minStake;
        uint256 discount; // In basis points (100 = 1%)
        uint256 lockDuration;
    }

    // Ecosystem integration
    struct EcosystemNFT {
        address collection;
        uint256 minBalance;
        uint256 discount; // In basis points
        uint256 maxMintsPerHolder;
        bool isActive;
    }

    // Rate limiting
    struct RateLimit {
        uint256 lastActionTime;
        uint256 count;
        uint256 windowStart;
    }

    // Storage
    mapping(uint256 => Series) public series;
    mapping(address => mapping(uint256 => uint256)) public userMints; // user => seriesId => mintCount
    mapping(address => RateLimit) public mintLimits;
    
    StakingTier[] public stakingTiers;
    mapping(address => EcosystemNFT) public ecosystemCollections;
    
    // Constants
    uint256 public constant MAX_DISCOUNT = 5000; // 50% max discount
    uint256 public constant RATE_LIMIT_WINDOW = 1 hours;
    uint256 public constant MAX_MINTS_PER_WINDOW = 5;
    uint256 public constant MIN_STAKE_DURATION = 7 days;
    
    // State variables
    uint256 public nextTokenId;
    uint256 public currentSeriesId;
    address public treasury;
    bool public emergencyMode;

    // Events
    event SeriesCreated(uint256 indexed seriesId, uint256 basePrice, uint256 maxSupply);
    event NFTMinted(
        address indexed minter, 
        uint256 indexed seriesId, 
        uint256 tokenId, 
        uint256 price,
        uint256 discount
    );
    event EcosystemCollectionAdded(address indexed collection, uint256 discount);
    event EmergencyModeActivated(uint256 timestamp);
    event StakingTierAdded(uint256 minStake, uint256 discount, uint256 lockDuration);

    constructor(
        address _ikigaiToken,
        address _bera,
        address _treasury
    ) {
        ikigaiToken = IkigaiTokenV2(_ikigaiToken);
        BERA = IERC20(_bera);
        treasury = _treasury;
        
        // Initialize base staking tiers
        stakingTiers.push(StakingTier(1000 ether, 500, 7 days));  // 1k tokens = 5% off
        stakingTiers.push(StakingTier(5000 ether, 1000, 14 days)); // 5k tokens = 10% off
        stakingTiers.push(StakingTier(15000 ether, 2000, 21 days)); // 15k tokens = 20% off
    }

    function initialize(string memory name, string memory symbol) public initializer {
        __ERC721_init(name, symbol);
        __Ownable_init();
        nextTokenId = 1;
    }

    // Series Management
    function createSeries(
        uint256 basePrice,
        uint256 maxSupply,
        uint256 startTime,
        uint256 endTime,
        uint256 minStakeRequired,
        uint256 stakeDuration,
        uint256 burnPercentage
    ) external onlyOwner {
        require(burnPercentage <= 5000, "Max burn is 50%"); // Safety check
        require(endTime > startTime, "Invalid time range");
        
        currentSeriesId++;
        Series storage newSeries = series[currentSeriesId];
        
        newSeries.id = currentSeriesId;
        newSeries.basePrice = basePrice;
        newSeries.maxSupply = maxSupply;
        newSeries.startTime = startTime;
        newSeries.endTime = endTime;
        newSeries.minStakeRequired = minStakeRequired;
        newSeries.stakeDuration = stakeDuration;
        newSeries.burnPercentage = burnPercentage;
        
        emit SeriesCreated(currentSeriesId, basePrice, maxSupply);
    }

    // Minting Logic
    function mint(uint256 seriesId) external nonReentrant whenNotPaused {
        Series storage currentSeries = series[seriesId];
        require(currentSeries.isActive, "Series not active");
        require(block.timestamp >= currentSeries.startTime, "Series not started");
        require(block.timestamp <= currentSeries.endTime, "Series ended");
        require(currentSeries.currentSupply < currentSeries.maxSupply, "Series sold out");
        
        // Whitelist check
        if (currentSeries.whitelistOnly) {
            require(currentSeries.whitelist[msg.sender], "Not whitelisted");
        }
        
        // Rate limiting
        _checkAndUpdateRateLimit(msg.sender);
        
        // Calculate final price with discounts
        uint256 finalPrice = calculateFinalPrice(seriesId, msg.sender);
        
        // Handle payment and minting
        if (currentSeries.id == 1) { // Genesis series uses BERA
            require(BERA.transferFrom(msg.sender, address(this), finalPrice), "BERA transfer failed");
            _handleBERAPayment(finalPrice, currentSeries.burnPercentage);
        } else { // Other series use IKIGAI
            require(ikigaiToken.transferFrom(msg.sender, address(this), finalPrice), "IKIGAI transfer failed");
            _handleIKIGAIPayment(finalPrice, currentSeries.burnPercentage);
        }
        
        // Mint NFT
        uint256 tokenId = nextTokenId++;
        _mint(msg.sender, tokenId);
        currentSeries.currentSupply++;
        userMints[msg.sender][seriesId]++;
        
        emit NFTMinted(msg.sender, seriesId, tokenId, finalPrice, 0);
    }

    // Price Calculation
    function calculateFinalPrice(uint256 seriesId, address user) public view returns (uint256) {
        Series storage currentSeries = series[seriesId];
        uint256 basePrice = currentSeries.basePrice;
        uint256 totalDiscount = 0;
        
        // Staking discount
        if (currentSeries.allowsStakingDiscount) {
            totalDiscount += calculateStakingDiscount(user);
        }
        
        // Ecosystem discount
        if (currentSeries.allowsEcosystemDiscount) {
            totalDiscount += calculateEcosystemDiscount(user);
        }
        
        // Cap total discount
        totalDiscount = Math.min(totalDiscount, MAX_DISCOUNT);
        
        return basePrice - ((basePrice * totalDiscount) / 10000);
    }

    // Discount Calculations
    function calculateStakingDiscount(address user) public view returns (uint256) {
        uint256 stakedAmount = ikigaiToken.balanceOf(user);
        
        for (uint256 i = stakingTiers.length; i > 0; i--) {
            if (stakedAmount >= stakingTiers[i-1].minStake) {
                return stakingTiers[i-1].discount;
            }
        }
        return 0;
    }

    function calculateEcosystemDiscount(address user) public view returns (uint256) {
        uint256 maxDiscount = 0;
        
        for (uint256 i = 0; i < ecosystemCollections.length; i++) {
            EcosystemNFT storage eco = ecosystemCollections[i];
            if (eco.isActive) {
                IERC721 nft = IERC721(eco.collection);
                if (nft.balanceOf(user) >= eco.minBalance) {
                    maxDiscount = Math.max(maxDiscount, eco.discount);
                }
            }
        }
        
        return maxDiscount;
    }

    // Payment Handling
    function _handleBERAPayment(uint256 amount, uint256 burnPercentage) internal {
        uint256 burnAmount = (amount * burnPercentage) / 10000;
        uint256 treasuryAmount = amount - burnAmount;
        
        // Send to treasury
        BERA.transfer(treasury, treasuryAmount);
        
        // Handle burn by sending to dead address
        if (burnAmount > 0) {
            BERA.transfer(address(0xdead), burnAmount);
        }
    }

    function _handleIKIGAIPayment(uint256 amount, uint256 burnPercentage) internal {
        uint256 burnAmount = (amount * burnPercentage) / 10000;
        uint256 treasuryAmount = amount - burnAmount;
        
        // Send to treasury
        ikigaiToken.transfer(treasury, treasuryAmount);
        
        // Burn tokens
        if (burnAmount > 0) {
            ikigaiToken.burn(burnAmount);
        }
    }

    // Rate Limiting
    function _checkAndUpdateRateLimit(address user) internal {
        RateLimit storage limit = mintLimits[user];
        
        if (block.timestamp >= limit.windowStart + RATE_LIMIT_WINDOW) {
            // Reset window
            limit.windowStart = block.timestamp;
            limit.count = 1;
        } else {
            require(limit.count < MAX_MINTS_PER_WINDOW, "Rate limit exceeded");
            limit.count++;
        }
        
        limit.lastActionTime = block.timestamp;
    }

    // Admin Functions
    function setEmergencyMode(bool enabled) external onlyOwner {
        emergencyMode = enabled;
        if (enabled) {
            _pause();
            emit EmergencyModeActivated(block.timestamp);
        } else {
            _unpause();
        }
    }

    function addEcosystemCollection(
        address collection,
        uint256 minBalance,
        uint256 discount,
        uint256 maxMints
    ) external onlyOwner {
        require(discount <= 3000, "Max discount 30%");
        
        ecosystemCollections[collection] = EcosystemNFT({
            collection: collection,
            minBalance: minBalance,
            discount: discount,
            maxMintsPerHolder: maxMints,
            isActive: true
        });
        
        emit EcosystemCollectionAdded(collection, discount);
    }

    function addStakingTier(
        uint256 minStake,
        uint256 discount,
        uint256 lockDuration
    ) external onlyOwner {
        require(discount <= 3000, "Max discount 30%");
        require(lockDuration >= MIN_STAKE_DURATION, "Lock too short");
        
        stakingTiers.push(StakingTier(minStake, discount, lockDuration));
        
        emit StakingTierAdded(minStake, discount, lockDuration);
    }

    // View Functions
    function getSeriesInfo(uint256 seriesId) external view returns (
        uint256 basePrice,
        uint256 maxSupply,
        uint256 currentSupply,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        uint256 minStakeRequired,
        uint256 stakeDuration,
        uint256 burnPercentage
    ) {
        Series storage s = series[seriesId];
        return (
            s.basePrice,
            s.maxSupply,
            s.currentSupply,
            s.startTime,
            s.endTime,
            s.isActive,
            s.minStakeRequired,
            s.stakeDuration,
            s.burnPercentage
        );
    }
} 