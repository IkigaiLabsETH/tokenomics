// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IkigaiToken.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./IkigaiRewards.sol";

/// @title IkigaiNFT - NFT contract with fee charging, integrated staking, and flywheel reward distribution
contract IkigaiNFT is Initializable, ERC721Upgradeable, OwnableUpgradeable, ReentrancyGuard, Pausable {
    // --- Structs for better data organization and gas optimization ---
    struct StakingInfo {
        uint256 balance;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
        uint256 lastClaimTime;
        uint256 stakeTimestamp;
    }

    struct PriorityConfig {
        uint256 discount;     // Basis points (e.g., 1000 = 10%)
        uint256 duration;     // Duration in seconds
        uint256 startTime;    // Start timestamp
        uint256 maxPerNFT;    // Max mints per BeraChain NFT
    }

    struct FeeConfig {
        uint256 polFee;       // Protocol Owned Liquidity fee
        uint256 rewardFee;    // Staking reward fee
        uint256 denominator;  // Fee denominator
    }

    // --- Additional Structs ---
    struct TierConfig {
        uint256 minStake;      // Minimum stake for tier
        uint256 multiplier;    // Reward multiplier (basis points)
        uint256 lockDuration;  // Lock duration in seconds
    }

    struct RateLimit {
        uint256 lastActionTime;
        uint256 actionCount;
        uint256 windowStart;
    }

    // --- Immutable state variables ---
    IkigaiToken public immutable ikigaiToken;
    IERC20 public immutable BERA;
    IERC721 public immutable beraNFT;
    IkigaiRewards public rewards;

    // --- Storage variables ---
    address public treasury;
    uint256 public salePriceBERA;
    uint256 public nextTokenId;
    
    // Staking state
    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;
    uint256 public undistributedRewards;

    // Priority minting config
    PriorityConfig public priorityConfig;
    
    // Fee configuration
    FeeConfig public constant FEES = FeeConfig({
        polFee: 20,        // 2%
        rewardFee: 13,     // 1.3%
        denominator: 1000  // Base 1000 for percentages
    });

    // Time constants
    uint256 private constant WEEK = 1 weeks;

    // --- Mappings ---
    mapping(address => StakingInfo) public stakingInfo;
    mapping(uint256 => uint256) public beraNFTMintCount;

    // Additional security features
    uint256 private constant MAX_INT = type(uint256).max;
    uint256 public maxSupply;
    mapping(address => bool) public blacklisted;
    
    // Circuit breaker flags
    bool public stakingPaused;
    bool public mintingPaused;

    // Batch operation limits
    uint256 public constant MAX_BATCH_SIZE = 20;

    // --- Enhanced Storage ---
    TierConfig[4] public tiers;  // Staking tiers
    mapping(address => RateLimit) public mintRateLimits;
    mapping(address => RateLimit) public stakeRateLimits;
    
    uint256 public constant RATE_LIMIT_PERIOD = 1 hours;
    uint256 public constant MAX_MINTS_PER_PERIOD = 5;
    uint256 public constant MAX_STAKES_PER_PERIOD = 10;

    uint256 public mintPrice;
    uint256 public priorityDiscount; // basis points
    
    uint256 public constant MAX_PRIORITY_MINTS = 2;

    // Add series management
    struct Series {
        uint256 id;
        uint256 price;          // In IKIGAI tokens
        uint256 maxSupply;
        uint256 currentSupply;
        uint256 startTime;
        bool isGenesis;         // Genesis uses BERA, others use IKIGAI
        bool active;
        uint256 requiredStake;    // Required IKIGAI stake to mint
        uint256 stakeDuration;    // How long stake must be locked
    }

    mapping(uint256 => Series) public series;
    uint256 public currentSeriesId;

    // Add to state variables
    mapping(uint256 => mapping(address => bool)) public seriesWhitelist;
    mapping(uint256 => bool) public whitelistRequired;
    uint256 public whitelistPrice; // Discount for whitelisted users

    // Add discount tiers
    struct MintDiscount {
        uint256 minStake;
        uint256 discount; // basis points
    }

    MintDiscount[] public mintDiscounts;

    // Add new structs
    struct EcosystemNFT {
        address collection;    // Collection address
        uint256 tierLevel;    // Priority tier (1-3)
        uint256 discount;     // Discount basis points
        bool active;          // Active status
        uint256 minBalance;   // Minimum NFTs required
        uint256 maxMints;     // Maximum mints allowed
    }

    struct UserEcosystemInfo {
        uint256 mintCount;    // Number of mints used
        uint256 lastMintTime; // Last mint timestamp
        uint256 tierLevel;    // Current tier level
        bool whitelisted;     // Whitelist status
    }

    // Add state variables
    mapping(address => EcosystemNFT) public ecosystemCollections;
    mapping(address => mapping(address => UserEcosystemInfo)) public userEcosystemInfo;
    address[] public supportedCollections;

    uint256 public constant TIER1_DISCOUNT = 2500; // 25%
    uint256 public constant TIER2_DISCOUNT = 1500; // 15%
    uint256 public constant TIER3_DISCOUNT = 1000; // 10%

    // Add security-focused modifiers and constants
    modifier validMint(uint256 tokenId) {
        require(tokenId > 0 && tokenId <= maxSupply, "Invalid token ID");
        require(!_exists(tokenId), "Token already exists");
        _;
    }

    modifier validStake(uint256 amount) {
        require(amount >= tiers[0].minStake, "Below minimum stake");
        require(amount <= maxStakeAmount, "Exceeds max stake");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Account blacklisted");
        _;
    }

    // Add security constants
    uint256 private constant MAX_STAKE_AMOUNT = 1_000_000 * 1e18; // 1M tokens max stake
    uint256 private constant EMERGENCY_TIMEOUT = 24 hours;
    uint256 private constant MIN_STAKE_DURATION = 1 days;

    // Add to state variables
    bool public emergencyMode;
    uint256 public lastEmergencyAction;
    uint256 public maxStakeAmount;

    // Add security events
    event SecurityIncident(
        address indexed account,
        string incidentType,
        uint256 timestamp
    );

    event EmergencyModeEnabled(uint256 timestamp);
    event EmergencyModeDisabled(uint256 timestamp);
    event RateLimitExceeded(
        address indexed account,
        string actionType,
        uint256 count
    );

    // --- Events ---
    event NFTPurchased(address indexed buyer, uint256 tokenId, uint256 fee, uint256 sellerAmount);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event PriorityMint(address indexed buyer, uint256 beraNFTId, uint256 tokenId);
    event PriorityPeriodSet(uint256 startTime, uint256 duration);
    event BlacklistUpdated(address indexed account, bool status);
    event CircuitBreakerTriggered(string indexed operation, bool status);
    event BatchStaked(address indexed user, uint256 amount, uint256 count);
    event BatchWithdrawn(address indexed user, uint256 amount, uint256 count);
    event TierConfigUpdated(uint256 tierId, uint256 minStake, uint256 multiplier, uint256 lockDuration);
    event EmergencyWithdrawal(address indexed user, uint256 amount);
    event EcosystemCollectionAdded(
        address indexed collection,
        uint256 tierLevel,
        uint256 discount
    );
    event EcosystemMint(
        address indexed user,
        address indexed collection,
        uint256 tokenId,
        uint256 discount
    );

    /// @notice Modified initialization with additional security parameters
    function initialize(
        address _ikigaiToken, 
        address _bera,
        address _treasury,
        uint256 _salePriceBERA,
        address _beraNFT,
        uint256 _priorityDuration,
        uint256 _priorityDiscount,
        uint256 _maxSupply,
        address _rewards
    ) public initializer {
        __ERC721_init("IkigaiNFT", "IKNFT");
        __Ownable_init();
        
        ikigaiToken = IkigaiToken(_ikigaiToken);
        BERA = IERC20(_bera);
        beraNFT = IERC721(_beraNFT);
        treasury = _treasury;
        salePriceBERA = _salePriceBERA;

        priorityConfig = PriorityConfig({
            discount: _priorityDiscount,
            duration: _priorityDuration,
            startTime: 0,
            maxPerNFT: 2
        });

        nextTokenId = 1;
        maxSupply = _maxSupply;

        // Initialize tiers
        tiers[0] = TierConfig(1000 ether, 10000, 1 weeks);    // Base tier: 1x rewards
        tiers[1] = TierConfig(5000 ether, 12500, 2 weeks);    // Silver: 1.25x rewards
        tiers[2] = TierConfig(10000 ether, 15000, 3 weeks);   // Gold: 1.5x rewards
        tiers[3] = TierConfig(25000 ether, 20000, 4 weeks);   // Diamond: 2x rewards

        rewards = IkigaiRewards(_rewards);
    }

    // --- Enhanced Security Modifiers ---

    modifier whenStakingNotPaused() {
        require(!stakingPaused, "Staking is paused");
        _;
    }

    modifier whenMintingNotPaused() {
        require(!mintingPaused, "Minting is paused");
        _;
    }

    /// @notice Internal function to handle minting logic
    function _handleMint(
        address buyer, 
        uint256 price
    ) private returns (uint256 tokenId) {
        require(nextTokenId <= maxSupply, "Max supply reached");
        uint256 polFee = (price * FEES.polFee) / FEES.denominator;
        uint256 rewardFee = (price * FEES.rewardFee) / FEES.denominator;
        uint256 sellerAmount = price - polFee - rewardFee;

        // Handle transfers
        BERA.transfer(treasury, polFee);
        BERA.transfer(owner(), sellerAmount);

        // Mint NFT
        tokenId = nextTokenId++;
        _mint(buyer, tokenId);

        // Handle rewards
        _handleRewards(rewardFee);

        emit NFTPurchased(buyer, tokenId, rewardFee, sellerAmount);
    }

    /// @notice Internal function to handle reward distribution
    function _handleRewards(uint256 rewardFee) private {
        if (totalStaked == 0) {
            undistributedRewards += rewardFee;
        } else {
            uint256 totalFee = rewardFee + undistributedRewards;
            rewardPerTokenStored += (totalFee * 1e18) / totalStaked;
            undistributedRewards = 0;
        }
        ikigaiToken.mint(address(this), rewardFee);
    }

    /// @notice Start priority minting period
    function startPriorityPeriod() external onlyOwner {
        priorityConfig.startTime = block.timestamp;
        emit PriorityPeriodSet(priorityConfig.startTime, priorityConfig.duration);
    }

    /// @notice Buy NFT with priority access
    function priorityMint(uint256 beraNFTId) external nonReentrant {
        require(block.timestamp < priorityConfig.startTime + priorityConfig.duration, "Priority ended");
        require(beraNFT.ownerOf(beraNFTId) == msg.sender, "Not owner");
        require(beraNFTMintCount[beraNFTId] < priorityConfig.maxPerNFT, "Max mints reached");

        uint256 discountedPrice = salePriceBERA - ((salePriceBERA * priorityConfig.discount) / 10000);
        require(BERA.transferFrom(msg.sender, address(this), discountedPrice), "Transfer failed");

        uint256 tokenId = _handleMint(msg.sender, discountedPrice);
        beraNFTMintCount[beraNFTId]++;
        
        rewards.handleMintReward(msg.sender, discountedPrice);
        emit PriorityMint(msg.sender, beraNFTId, tokenId);
    }

    /// @notice Regular buy function
    function buyNFT() external nonReentrant {
        require(
            block.timestamp >= priorityConfig.startTime + priorityConfig.duration || 
            priorityConfig.startTime == 0,
            "Priority active"
        );
        require(BERA.transferFrom(msg.sender, address(this), salePriceBERA), "Transfer failed");

        _handleMint(msg.sender, salePriceBERA);
    }

    /// @notice Stake a specified amount of Ikigai tokens. Caller must approve token transfer beforehand.
    function stake(uint256 amount) external 
        whenStakingNotPaused 
        notBlacklisted(msg.sender)
        validStake(amount)
        nonReentrant 
    {
        require(!emergencyMode, "System in emergency mode");
        require(_checkStakeRateLimit(msg.sender), "Rate limit exceeded");
        
        // Verify balance and allowance
        require(
            ikigaiToken.balanceOf(msg.sender) >= amount &&
            ikigaiToken.allowance(msg.sender, address(this)) >= amount,
            "Insufficient balance/allowance"
        );

        // Update rate limit first
        _updateStakeRateLimit(msg.sender);

        // Get tier info
        uint256 tier = getUserTier(msg.sender);
        uint256 lockPeriod = tiers[tier].lockDuration;

        // Update stake info with safety checks
        StakingInfo storage info = stakingInfo[msg.sender];
        uint256 newBalance = info.balance + amount;
        require(newBalance <= MAX_STAKE_AMOUNT, "Exceeds max stake");
        
        // Update state
        info.balance = newBalance;
        info.stakeTimestamp = uint96(block.timestamp + lockPeriod);
        totalStaked += amount;

        // Safe transfer with return value check
        require(ikigaiToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Update rewards safely
        try rewards.handleStakeReward(msg.sender, amount) {
            // Success
        } catch {
            // Log failure but don't revert
            emit SecurityIncident(msg.sender, "reward_update_failed", block.timestamp);
        }

        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraw staked tokens. Withdrawal is allowed only if tokens have been locked for at least 1 week.
    function withdrawStake(uint256 amount) external {
        require(stakingInfo[msg.sender].balance >= amount, "Not enough staked");
        require(block.timestamp >= stakingInfo[msg.sender].stakeTimestamp + WEEK, "Stake locked for at least 1 week");

        updateReward(msg.sender);
        stakingInfo[msg.sender].balance -= amount;
        totalStaked -= amount;
        ikigaiToken.transfer(msg.sender, amount);

        // Reset the stake timestamp if fully withdrawn.
        if (stakingInfo[msg.sender].balance == 0) {
            stakingInfo[msg.sender].stakeTimestamp = 0;
        }

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Claim accumulated staking rewards. Claims can be made only once per week.
    function claimRewards() external {
        require(block.timestamp >= stakingInfo[msg.sender].lastClaimTime + WEEK, "Claim available once per week");
        updateReward(msg.sender);

        uint256 reward = stakingInfo[msg.sender].rewards;
        require(reward > 0, "No rewards available");

        stakingInfo[msg.sender].rewards = 0;
        stakingInfo[msg.sender].lastClaimTime = block.timestamp;
        ikigaiToken.transfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    /// @notice Update the reward accounting for an account.
    function updateReward(address account) internal {
        stakingInfo[account].rewards = earned(account);
        stakingInfo[account].rewardPerTokenPaid = rewardPerTokenStored;
    }

    /// @notice Calculate the total earned rewards for an account.
    function earned(address account) public view returns (uint256) {
        StakingInfo storage info = stakingInfo[account];
        
        if (info.balance == 0) return info.rewards;
        
        unchecked {
            uint256 baseReward = info.rewards + (
                (info.balance * (rewardPerTokenStored - info.rewardPerTokenPaid)) / 1e18
            );
            return getMultipliedReward(account, baseReward);
        }
    }

    /// @notice Batch stake tokens for gas optimization
    function batchStake(uint256[] calldata amounts) external 
        nonReentrant 
        whenStakingNotPaused 
        notBlacklisted(msg.sender) 
    {
        require(amounts.length <= MAX_BATCH_SIZE, "Batch too large");
        require(!emergencyMode, "System in emergency mode");
        
        uint256 totalAmount;
        
        // Calculate total with overflow checks
        for(uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Invalid amount");
            totalAmount = _safeAdd(totalAmount, amounts[i]);
            require(totalAmount <= MAX_STAKE_AMOUNT, "Exceeds max stake");
        }
        
        // Verify balance and allowance
        require(
            ikigaiToken.balanceOf(msg.sender) >= totalAmount &&
            ikigaiToken.allowance(msg.sender, address(this)) >= totalAmount,
            "Insufficient balance/allowance"
        );
        
        // Update state
        StakingInfo storage info = stakingInfo[msg.sender];
        info.balance = _safeAdd(info.balance, totalAmount);
        totalStaked = _safeAdd(totalStaked, totalAmount);
        
        // Safe transfer
        require(ikigaiToken.transferFrom(msg.sender, address(this), totalAmount), "Transfer failed");
        
        emit BatchStaked(msg.sender, totalAmount, amounts.length);
    }

    /// @notice Emergency withdraw function
    function emergencyWithdraw() external nonReentrant notBlacklisted(msg.sender) {
        require(emergencyMode, "Not in emergency mode");
        
        StakingInfo storage info = stakingInfo[msg.sender];
        require(info.balance > 0, "Nothing to withdraw");
        
        uint256 amount = info.balance;
        
        // Update state before transfer
        info.balance = 0;
        totalStaked -= amount;
        
        // Reset staking data
        info.rewards = 0;
        info.stakeTimestamp = 0;
        info.lastClaimTime = 0;
        
        // Safe transfer
        require(ikigaiToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit EmergencyWithdrawal(msg.sender, amount);
    }

    /// @notice Update blacklist status
    function updateBlacklist(address account, bool status) external onlyOwner {
        blacklisted[account] = status;
        emit BlacklistUpdated(account, status);
    }

    /// @notice Circuit breaker for staking
    function setStakingPaused(bool status) external onlyOwner {
        stakingPaused = status;
        emit CircuitBreakerTriggered("staking", status);
    }

    /// @notice Circuit breaker for minting
    function setMintingPaused(bool status) external onlyOwner {
        mintingPaused = status;
        emit CircuitBreakerTriggered("minting", status);
    }

    /// @notice Get all staking info for an account in one call
    function getStakingInfo(address account) external view returns (
        uint256 stakedBalance,
        uint256 earnedRewards,
        uint256 timeUntilUnlock,
        uint256 timeUntilNextClaim
    ) {
        StakingInfo storage info = stakingInfo[account];
        
        stakedBalance = info.balance;
        earnedRewards = earned(account);
        
        uint256 unlockTime = info.stakeTimestamp + WEEK;
        timeUntilUnlock = block.timestamp >= unlockTime ? 0 : unlockTime - block.timestamp;
        
        uint256 nextClaim = info.lastClaimTime + WEEK;
        timeUntilNextClaim = block.timestamp >= nextClaim ? 0 : nextClaim - block.timestamp;
    }

    // --- Rate Limiting ---
    modifier rateLimitMint() {
        RateLimit storage limit = mintRateLimits[msg.sender];
        if (block.timestamp - limit.lastActionTime >= RATE_LIMIT_PERIOD) {
            limit.actionCount = 1;
            limit.lastActionTime = block.timestamp;
        } else {
            require(limit.actionCount < MAX_MINTS_PER_PERIOD, "Rate limit exceeded");
            limit.actionCount++;
        }
        _;
    }

    modifier rateLimitStake() {
        RateLimit storage limit = stakeRateLimits[msg.sender];
        if (block.timestamp - limit.lastActionTime >= RATE_LIMIT_PERIOD) {
            limit.actionCount = 1;
            limit.lastActionTime = block.timestamp;
        } else {
            require(limit.actionCount < MAX_STAKES_PER_PERIOD, "Rate limit exceeded");
            limit.actionCount++;
        }
        _;
    }

    // --- Tiered Staking Functions ---
    function getUserTier(address user) public view returns (uint256) {
        uint256 stakedAmount = stakingInfo[user].balance;
        for (uint256 i = 3; i >= 0; i--) {
            if (stakedAmount >= tiers[i].minStake) {
                return i;
            }
        }
        return 0;
    }

    function getMultipliedReward(address user, uint256 baseReward) internal view returns (uint256) {
        uint256 tier = getUserTier(user);
        return (baseReward * tiers[tier].multiplier) / 10000;
    }

    // --- Additional Security Functions ---
    function setTierConfig(
        uint256 tierId,
        uint256 minStake,
        uint256 multiplier,
        uint256 lockDuration
    ) external onlyOwner {
        require(tierId < 4, "Invalid tier");
        require(multiplier <= 30000, "Multiplier too high"); // Max 3x
        require(lockDuration <= 52 weeks, "Lock too long"); // Max 1 year

        tiers[tierId] = TierConfig(minStake, multiplier, lockDuration);
        emit TierConfigUpdated(tierId, minStake, multiplier, lockDuration);
    }

    // --- Additional View Functions ---
    function getTierInfo(address user) external view returns (
        uint256 currentTier,
        uint256 nextTierMinStake,
        uint256 currentMultiplier,
        uint256 timeUntilUnlock
    ) {
        currentTier = getUserTier(user);
        currentMultiplier = tiers[currentTier].multiplier;
        
        if (currentTier < 3) {
            nextTierMinStake = tiers[currentTier + 1].minStake;
        } else {
            nextTierMinStake = type(uint256).max;
        }

        StakingInfo storage info = stakingInfo[user];
        timeUntilUnlock = block.timestamp >= info.stakeTimestamp ? 
            0 : info.stakeTimestamp - block.timestamp;
    }

    // Add series management
    function createSeries(
        uint256 price,
        uint256 maxSupply,
        uint256 startTime,
        bool isGenesis,
        uint256 requiredStake,
        uint256 stakeDuration
    ) external onlyOwner {
        currentSeriesId++;
        
        series[currentSeriesId] = Series({
            id: currentSeriesId,
            price: price,
            maxSupply: maxSupply,
            currentSupply: 0,
            startTime: startTime,
            isGenesis: isGenesis,
            active: false,
            requiredStake: requiredStake,
            stakeDuration: stakeDuration
        });

        emit SeriesCreated(currentSeriesId, price, maxSupply, isGenesis);
    }

    // Modify mint function to handle different series
    function mint(uint256 seriesId) external nonReentrant whenNotPaused {
        Series storage currentSeries = series[seriesId];
        require(currentSeries.active, "Series not active");
        require(currentSeries.currentSupply < currentSeries.maxSupply, "Series sold out");
        
        if (whitelistRequired[seriesId]) {
            require(seriesWhitelist[seriesId][msg.sender], "Not whitelisted");
        }

        if (!currentSeries.isGenesis && currentSeries.requiredStake > 0) {
            StakingInfo storage stakeInfo = stakingInfo[msg.sender];
            require(stakeInfo.balance >= currentSeries.requiredStake, "Insufficient stake");
            require(
                block.timestamp >= stakeInfo.stakeTimestamp + currentSeries.stakeDuration,
                "Stake duration not met"
            );
        }

        uint256 price = currentSeries.price;
        if (seriesWhitelist[seriesId][msg.sender]) {
            price = price - ((price * whitelistPrice) / 10000); // Apply whitelist discount
        }

        if (currentSeries.isGenesis) {
            require(BERA.transferFrom(msg.sender, address(this), price), "BERA transfer failed");
            rewards.handleMintReward(msg.sender, price);
        } else {
            require(ikigaiToken.transferFrom(msg.sender, address(this), price), "IKIGAI transfer failed");
            
            // Enhanced burn mechanism for non-genesis
            uint256 burnAmount = (price * 20) / 100; // 20% burn
            uint256 treasuryAmount = (price * 60) / 100; // 60% to treasury
            uint256 stakingAmount = price - burnAmount - treasuryAmount; // 20% to staking rewards
            
            ikigaiToken.burn(burnAmount);
            ikigaiToken.transfer(treasury, treasuryAmount);
            ikigaiToken.transfer(address(rewards), stakingAmount);
            
            // Update staking rewards
            rewards.notifyRewardAmount(stakingAmount);
        }

        currentSeries.currentSupply++;
        _mint(msg.sender, nextTokenId++);
    }

    // Add whitelist management
    function setWhitelistStatus(
        uint256 seriesId,
        address[] calldata users,
        bool status
    ) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            seriesWhitelist[seriesId][users[i]] = status;
            emit WhitelistUpdated(seriesId, users[i], status);
        }
    }

    function setWhitelistRequired(uint256 seriesId, bool required) external onlyOwner {
        whitelistRequired[seriesId] = required;
        emit WhitelistRequirementSet(seriesId, required);
    }

    // Initialize discounts
    function initializeMintDiscounts() external onlyOwner {
        mintDiscounts.push(MintDiscount(5000 ether, 1000));  // 5k staked = 10% off
        mintDiscounts.push(MintDiscount(10000 ether, 2000)); // 10k staked = 20% off
        mintDiscounts.push(MintDiscount(25000 ether, 3000)); // 25k staked = 30% off
    }

    // Get user's discount
    function getMintDiscount(address user) public view returns (uint256) {
        uint256 stakedAmount = stakingInfo[user].balance;
        
        for (uint256 i = mintDiscounts.length; i > 0; i--) {
            if (stakedAmount >= mintDiscounts[i-1].minStake) {
                return mintDiscounts[i-1].discount;
            }
        }
        return 0;
    }

    // Add rate limit checks
    function _checkStakeRateLimit(address account) internal view returns (bool) {
        if (isExemptFromLimit[account]) return true;
        
        RateLimit storage limit = stakeRateLimits[account];
        
        // Reset window if needed
        if (block.timestamp >= limit.windowStart + 1 hours) {
            return true;
        }
        
        return limit.actionCount < MAX_STAKES_PER_HOUR;
    }

    function _updateStakeRateLimit(address account) internal {
        if (isExemptFromLimit[account]) return;
        
        RateLimit storage limit = stakeRateLimits[account];
        
        // Reset window if needed
        if (block.timestamp >= limit.windowStart + 1 hours) {
            limit.actionCount = 1;
            limit.windowStart = block.timestamp;
        } else {
            limit.actionCount++;
            if (limit.actionCount > MAX_STAKES_PER_HOUR) {
                emit RateLimitExceeded(account, "stake", limit.actionCount);
                revert("Rate limit exceeded");
            }
        }
        
        limit.lastActionTime = block.timestamp;
    }

    // Add emergency controls
    function enableEmergencyMode() external onlyOwner {
        emergencyMode = true;
        lastEmergencyAction = block.timestamp;
        emit EmergencyModeEnabled(block.timestamp);
    }

    function disableEmergencyMode() external onlyOwner {
        require(
            block.timestamp >= lastEmergencyAction + EMERGENCY_TIMEOUT,
            "Emergency timeout not elapsed"
        );
        emergencyMode = false;
        emit EmergencyModeDisabled(block.timestamp);
    }

    // Add safe math helpers
    function _safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "Add overflow");
        return c;
    }

    // Add ecosystem collection management
    function addEcosystemCollection(
        address collection,
        uint256 tierLevel,
        uint256 discount,
        uint256 minBalance,
        uint256 maxMints
    ) external onlyOwner {
        require(collection != address(0), "Invalid collection");
        require(tierLevel >= 1 && tierLevel <= 3, "Invalid tier");
        require(discount <= 3000, "Discount too high"); // Max 30%
        
        ecosystemCollections[collection] = EcosystemNFT({
            collection: collection,
            tierLevel: tierLevel,
            discount: discount,
            active: true,
            minBalance: minBalance,
            maxMints: maxMints
        });
        
        supportedCollections.push(collection);
        emit EcosystemCollectionAdded(collection, tierLevel, discount);
    }

    // Add ecosystem minting
    function ecosystemMint(address collection) external nonReentrant whenMintingNotPaused {
        EcosystemNFT storage eco = ecosystemCollections[collection];
        require(eco.active, "Collection not supported");
        
        // Check NFT balance
        IERC721 nft = IERC721(collection);
        uint256 balance = nft.balanceOf(msg.sender);
        require(balance >= eco.minBalance, "Insufficient NFTs");
        
        // Check mint limits
        UserEcosystemInfo storage userInfo = userEcosystemInfo[collection][msg.sender];
        require(userInfo.mintCount < eco.maxMints, "Max mints reached");
        
        // Calculate price with ecosystem discount
        uint256 discountedPrice = calculateEcosystemPrice(collection, salePriceBERA);
        require(BERA.transferFrom(msg.sender, address(this), discountedPrice), "Transfer failed");
        
        // Mint NFT
        uint256 tokenId = _handleMint(msg.sender, discountedPrice);
        
        // Update user info
        userInfo.mintCount++;
        userInfo.lastMintTime = block.timestamp;
        
        emit EcosystemMint(msg.sender, collection, tokenId, eco.discount);
    }

    // Add price calculation with stackable discounts
    function calculateEcosystemPrice(
        address collection,
        uint256 basePrice
    ) public view returns (uint256) {
        EcosystemNFT storage eco = ecosystemCollections[collection];
        uint256 totalDiscount = eco.discount;
        
        // Add staking discount if applicable
        uint256 stakingDiscount = getMintDiscount(msg.sender);
        if (stakingDiscount > 0) {
            totalDiscount = Math.min(totalDiscount + stakingDiscount, 5000); // Max 50% total
        }
        
        return basePrice - ((basePrice * totalDiscount) / 10000);
    }

    // Add ecosystem tier checks
    function checkEcosystemAccess(
        address user,
        address collection
    ) public view returns (
        bool hasAccess,
        uint256 tierLevel,
        uint256 discount
    ) {
        EcosystemNFT storage eco = ecosystemCollections[collection];
        if (!eco.active) return (false, 0, 0);
        
        IERC721 nft = IERC721(collection);
        uint256 balance = nft.balanceOf(user);
        
        if (balance >= eco.minBalance) {
            return (true, eco.tierLevel, eco.discount);
        }
        
        return (false, 0, 0);
    }

    // Add batch ecosystem checks
    function getUserEcosystemTiers(
        address user
    ) external view returns (
        address[] memory collections,
        uint256[] memory tiers,
        uint256[] memory discounts
    ) {
        uint256 count = supportedCollections.length;
        collections = new address[](count);
        tiers = new uint256[](count);
        discounts = new uint256[](count);
        
        for (uint256 i = 0; i < count; i++) {
            address collection = supportedCollections[i];
            (bool hasAccess, uint256 tier, uint256 discount) = checkEcosystemAccess(
                user,
                collection
            );
            
            if (hasAccess) {
                collections[i] = collection;
                tiers[i] = tier;
                discounts[i] = discount;
            }
        }
    }

    // Add ecosystem whitelist management
    function setEcosystemWhitelist(
        address[] calldata users,
        address collection,
        bool status
    ) external onlyOwner {
        require(ecosystemCollections[collection].active, "Collection not supported");
        
        for (uint256 i = 0; i < users.length; i++) {
            userEcosystemInfo[collection][users[i]].whitelisted = status;
        }
    }
}