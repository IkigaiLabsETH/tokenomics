// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IIkigaiOracleV2.sol";
import "../interfaces/IIkigaiTreasuryV2.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";

contract IkigaiVaultExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant VAULT_MANAGER = keccak256("VAULT_MANAGER");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    struct VaultStrategy {
        uint256 targetAllocation;  // Target allocation percentage
        uint256 currentAllocation; // Current allocation
        uint256 maxDrawdown;       // Maximum allowed drawdown
        uint256 performanceFee;    // Performance fee (basis points)
        uint256 lastRebalance;     // Last rebalance timestamp
        bool isActive;             // Whether strategy is active
    }

    struct AssetPosition {
        uint256 amount;           // Amount of asset
        uint256 entryPrice;      // Entry price
        uint256 lastValuation;   // Last valuation
        uint256 profitLoss;      // Unrealized P&L
        uint256 timestamp;       // Position timestamp
        bool isLong;             // Long/short position
    }

    struct RiskParameters {
        uint256 maxExposure;      // Maximum exposure per asset
        uint256 minLiquidity;     // Minimum liquidity required
        uint256 rebalanceThreshold; // Threshold for rebalancing
        uint256 slippageTolerance; // Maximum slippage allowed
        uint256 cooldownPeriod;    // Time between actions
    }

    struct StrategyParams {
        uint256 totalDebt;         // Total debt allocated
        uint256 totalGain;         // Total lifetime gain
        uint256 totalLoss;         // Total lifetime loss
        uint256 debtPaid;         // Total debt paid back
        uint256 lastHarvest;      // Last harvest timestamp
    }

    struct WithdrawalQueue {
        address[] strategies;      // Ordered withdrawal strategies
        uint256 totalWeight;      // Total withdrawal weight
        uint256 lastRebalance;    // Last rebalance timestamp
        bool active;              // Whether queue is active
    }

    struct VaultConfig {
        uint256 depositCap;      // Maximum deposits
        uint256 withdrawalFee;   // Withdrawal fee
        uint256 performanceFee;  // Performance fee
        uint256 managementFee;   // Management fee
        bool isActive;           // Vault status
    }

    struct UserPosition {
        uint256 principal;       // Deposited amount
        uint256 shares;          // Share balance
        uint256 lastDeposit;     // Last deposit time
        uint256 lastWithdraw;    // Last withdrawal time
        bool isLocked;           // Lock status
    }

    struct AssetAllocation {
        uint256 targetWeight;    // Target allocation
        uint256 currentWeight;   // Current allocation
        uint256 minWeight;       // Minimum weight
        uint256 maxWeight;       // Maximum weight
        bool isActive;           // Asset status
    }

    // State variables
    IERC20 public immutable ikigaiToken;
    IIkigaiOracleV2 public oracle;
    IIkigaiTreasuryV2 public treasury;
    IIkigaiMarketplaceV2 public marketplace;
    
    mapping(bytes32 => VaultStrategy) public strategies;
    mapping(address => mapping(bytes32 => AssetPosition)) public assetPositions;
    mapping(bytes32 => RiskParameters) public riskParams;
    mapping(address => StrategyParams) public strategyParams;
    mapping(bytes32 => WithdrawalQueue) public withdrawalQueues;
    mapping(address => uint256) public strategyDebtRatios;
    
    mapping(bytes32 => VaultConfig) public vaultConfigs;
    mapping(bytes32 => mapping(address => UserPosition)) public userPositions;
    mapping(address => AssetAllocation) public assetAllocations;
    mapping(address => bool) public supportedAssets;
    
    uint256 public totalValueLocked;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_PERFORMANCE_FEE = 2000; // 20%
    
    uint256 public totalDebt;
    uint256 public debtRatio;
    uint256 public lastReport;
    uint256 public lockedProfit;
    
    uint256 public constant MAX_BPS = 10000;
    uint256 public constant SECS_PER_YEAR = 31556952;
    uint256 public constant LOCKED_PROFIT_DECAY = 6 hours;
    
    uint256 public constant MAX_WITHDRAWAL_FEE = 500; // 5%
    uint256 public constant MIN_DEPOSIT = 100e18;
    
    // Events
    event StrategyUpdated(bytes32 indexed strategyId, uint256 allocation);
    event PositionOpened(address indexed asset, bytes32 strategyId, uint256 amount);
    event PositionClosed(address indexed asset, bytes32 strategyId, uint256 profit);
    event RebalanceExecuted(bytes32 indexed strategyId, uint256 timestamp);
    event StrategyAdded(address indexed strategy, uint256 debtRatio);
    event StrategyRevoked(address indexed strategy);
    event StrategyReported(address indexed strategy, uint256 gain, uint256 loss);
    event DebtRatioUpdated(address indexed strategy, uint256 debtRatio);
    event WithdrawalQueueSet(bytes32 indexed queueId, address[] strategies);
    event VaultConfigured(bytes32 indexed vaultId);
    event Deposited(bytes32 indexed vaultId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed vaultId, address indexed user, uint256 amount);
    event AllocationUpdated(address indexed asset, uint256 weight);

    constructor(
        address _ikigaiToken,
        address _oracle,
        address _treasury,
        address _marketplace
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        oracle = IIkigaiOracleV2(_oracle);
        treasury = IIkigaiTreasuryV2(_treasury);
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Strategy management
    function createStrategy(
        bytes32 strategyId,
        uint256 targetAllocation,
        uint256 maxDrawdown,
        uint256 performanceFee,
        RiskParameters calldata params
    ) external onlyRole(VAULT_MANAGER) {
        require(!strategies[strategyId].isActive, "Strategy exists");
        require(targetAllocation <= BASIS_POINTS, "Invalid allocation");
        require(performanceFee <= MAX_PERFORMANCE_FEE, "Fee too high");
        
        strategies[strategyId] = VaultStrategy({
            targetAllocation: targetAllocation,
            currentAllocation: 0,
            maxDrawdown: maxDrawdown,
            performanceFee: performanceFee,
            lastRebalance: block.timestamp,
            isActive: true
        });
        
        riskParams[strategyId] = params;
        
        emit StrategyUpdated(strategyId, targetAllocation);
    }

    function addStrategy(
        address strategy,
        uint256 _debtRatio,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest,
        uint256 performanceFee
    ) external onlyRole(VAULT_MANAGER) {
        require(strategy != address(0), "Invalid strategy");
        require(!strategies[strategy].isActive, "Strategy exists");
        require(_debtRatio + debtRatio <= MAX_BPS, "Exceeds max ratio");
        require(performanceFee <= 2000, "Fee too high"); // Max 20%
        
        strategies[strategy] = VaultStrategy({
            targetAllocation: 0,
            currentAllocation: 0,
            maxDrawdown: 0,
            performanceFee: performanceFee,
            lastRebalance: block.timestamp,
            isActive: true
        });
        
        debtRatio += _debtRatio;
        
        emit StrategyAdded(strategy, _debtRatio);
    }

    // Position management
    function openPosition(
        bytes32 strategyId,
        address asset,
        uint256 amount,
        bool isLong
    ) external onlyRole(STRATEGY_ROLE) nonReentrant whenNotPaused {
        VaultStrategy storage strategy = strategies[strategyId];
        RiskParameters storage params = riskParams[strategyId];
        
        require(strategy.isActive, "Strategy not active");
        require(
            block.timestamp >= strategy.lastRebalance + params.cooldownPeriod,
            "Cooldown active"
        );
        
        // Check exposure limits
        require(
            amount <= _calculateMaxExposure(strategyId, asset),
            "Exceeds exposure limit"
        );
        
        // Get asset price
        (uint256 price,,) = oracle.getLatestPrice(asset);
        require(price > 0, "Invalid price");
        
        // Create position
        assetPositions[asset][strategyId] = AssetPosition({
            amount: amount,
            entryPrice: price,
            lastValuation: price,
            profitLoss: 0,
            timestamp: block.timestamp,
            isLong: isLong
        });
        
        // Update strategy allocation
        strategy.currentAllocation += amount;
        
        emit PositionOpened(asset, strategyId, amount);
    }

    function closePosition(
        bytes32 strategyId,
        address asset
    ) external onlyRole(STRATEGY_ROLE) nonReentrant {
        VaultStrategy storage strategy = strategies[strategyId];
        AssetPosition storage position = assetPositions[asset][strategyId];
        
        require(position.amount > 0, "No position");
        
        // Calculate P&L
        (uint256 price,,) = oracle.getLatestPrice(asset);
        uint256 profitLoss = _calculateProfitLoss(position, price);
        
        // Handle fees
        uint256 performanceFee = 0;
        if (profitLoss > 0) {
            performanceFee = (profitLoss * strategy.performanceFee) / BASIS_POINTS;
            // Transfer fee
            _handlePerformanceFee(performanceFee);
        }
        
        // Update strategy allocation
        strategy.currentAllocation -= position.amount;
        
        // Clear position
        delete assetPositions[asset][strategyId];
        
        emit PositionClosed(asset, strategyId, profitLoss);
    }

    // Rebalancing functions
    function rebalanceStrategy(
        bytes32 strategyId
    ) external onlyRole(STRATEGY_ROLE) nonReentrant {
        VaultStrategy storage strategy = strategies[strategyId];
        RiskParameters storage params = riskParams[strategyId];
        
        require(strategy.isActive, "Strategy not active");
        require(
            block.timestamp >= strategy.lastRebalance + params.cooldownPeriod,
            "Cooldown active"
        );
        
        // Check if rebalance needed
        uint256 deviation = _calculateAllocationDeviation(strategyId);
        require(
            deviation >= params.rebalanceThreshold,
            "Rebalance not needed"
        );
        
        // Perform rebalancing
        _executeRebalance(strategyId);
        
        strategy.lastRebalance = block.timestamp;
        
        emit RebalanceExecuted(strategyId, block.timestamp);
    }

    // Strategy reporting
    function reportHarvest(
        uint256 gain,
        uint256 loss,
        uint256 debtPayment
    ) external onlyRole(STRATEGY_ROLE) {
        VaultStrategy storage strategy = strategies[msg.sender];
        require(strategy.isActive, "Strategy not active");
        require(
            block.timestamp >= strategy.lastRebalance + 1 days,
            "Too frequent"
        );
        
        StrategyParams storage params = strategyParams[msg.sender];
        
        // Update strategy params
        params.totalGain += gain;
        params.totalLoss += loss;
        params.debtPaid += debtPayment;
        params.lastHarvest = block.timestamp;
        
        // Update vault state
        totalDebt = totalDebt + gain - loss - debtPayment;
        lockedProfit += gain;
        
        // Handle fees
        if (gain > 0) {
            uint256 fee = (gain * strategy.performanceFee) / BASIS_POINTS;
            if (fee > 0) {
                require(
                    ikigaiToken.transfer(address(treasury), fee),
                    "Fee transfer failed"
                );
            }
        }
        
        strategy.lastRebalance = block.timestamp;
        lastReport = block.timestamp;
        
        emit StrategyReported(msg.sender, gain, loss);
    }

    // Withdrawal queue management
    function setWithdrawalQueue(
        bytes32 queueId,
        address[] calldata _strategies,
        uint256[] calldata weights
    ) external onlyRole(VAULT_MANAGER) {
        require(_strategies.length > 0, "Empty queue");
        require(_strategies.length == weights.length, "Length mismatch");
        
        uint256 totalWeight;
        for (uint256 i = 0; i < _strategies.length; i++) {
            require(strategies[_strategies[i]].isActive, "Invalid strategy");
            totalWeight += weights[i];
        }
        require(totalWeight == MAX_BPS, "Invalid weights");
        
        withdrawalQueues[queueId] = WithdrawalQueue({
            strategies: _strategies,
            totalWeight: totalWeight,
            lastRebalance: block.timestamp,
            active: true
        });
        
        emit WithdrawalQueueSet(queueId, _strategies);
    }

    // Vault configuration
    function configureVault(
        bytes32 vaultId,
        VaultConfig calldata config
    ) external onlyRole(VAULT_MANAGER) {
        require(config.withdrawalFee <= MAX_WITHDRAWAL_FEE, "Fee too high");
        require(config.performanceFee <= MAX_PERFORMANCE_FEE, "Fee too high");
        
        vaultConfigs[vaultId] = config;
        
        emit VaultConfigured(vaultId);
    }

    // Deposit handling
    function deposit(
        bytes32 vaultId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount >= MIN_DEPOSIT, "Below minimum");
        
        VaultConfig storage config = vaultConfigs[vaultId];
        require(config.isActive, "Vault inactive");
        
        UserPosition storage position = userPositions[vaultId][msg.sender];
        require(
            position.principal + amount <= config.depositCap,
            "Exceeds cap"
        );
        
        // Calculate shares
        uint256 shares = _calculateShares(vaultId, amount);
        
        // Transfer tokens
        IERC20(address(this)).transferFrom(msg.sender, address(this), amount);
        
        // Update position
        position.principal += amount;
        position.shares += shares;
        position.lastDeposit = block.timestamp;
        
        emit Deposited(vaultId, msg.sender, amount);
    }

    // Withdrawal handling
    function withdraw(
        bytes32 vaultId,
        uint256 shares
    ) external nonReentrant {
        UserPosition storage position = userPositions[vaultId][msg.sender];
        require(position.shares >= shares, "Insufficient shares");
        require(!position.isLocked, "Position locked");
        
        VaultConfig storage config = vaultConfigs[vaultId];
        
        // Calculate amount
        uint256 amount = _calculateWithdrawAmount(vaultId, shares);
        
        // Calculate fees
        uint256 withdrawalFee = (amount * config.withdrawalFee) / 10000;
        uint256 performanceFee = _calculatePerformanceFee(vaultId, amount);
        
        // Transfer tokens
        uint256 netAmount = amount - withdrawalFee - performanceFee;
        IERC20(address(this)).transfer(msg.sender, netAmount);
        
        // Update position
        position.shares -= shares;
        position.principal = (position.principal * position.shares) / (position.shares + shares);
        position.lastWithdraw = block.timestamp;
        
        emit Withdrawn(vaultId, msg.sender, netAmount);
    }

    // Asset allocation
    function updateAllocation(
        address asset,
        uint256 targetWeight,
        uint256 minWeight,
        uint256 maxWeight
    ) external onlyRole(ALLOCATOR_ROLE) {
        require(supportedAssets[asset], "Asset not supported");
        require(targetWeight <= maxWeight, "Invalid target");
        require(minWeight <= targetWeight, "Invalid min");
        
        AssetAllocation storage allocation = assetAllocations[asset];
        allocation.targetWeight = targetWeight;
        allocation.minWeight = minWeight;
        allocation.maxWeight = maxWeight;
        allocation.isActive = true;
        
        // Rebalance if needed
        _checkRebalance(asset);
        
        emit AllocationUpdated(asset, targetWeight);
    }

    // Internal functions
    function _calculateMaxExposure(
        bytes32 strategyId,
        address asset
    ) internal view returns (uint256) {
        RiskParameters storage params = riskParams[strategyId];
        return (totalValueLocked * params.maxExposure) / BASIS_POINTS;
    }

    function _calculateProfitLoss(
        AssetPosition storage position,
        uint256 currentPrice
    ) internal view returns (uint256) {
        if (position.isLong) {
            return currentPrice > position.entryPrice ?
                (currentPrice - position.entryPrice) * position.amount :
                0;
        } else {
            return position.entryPrice > currentPrice ?
                (position.entryPrice - currentPrice) * position.amount :
                0;
        }
    }

    function _calculateAllocationDeviation(
        bytes32 strategyId
    ) internal view returns (uint256) {
        VaultStrategy storage strategy = strategies[strategyId];
        
        if (strategy.targetAllocation >= strategy.currentAllocation) {
            return strategy.targetAllocation - strategy.currentAllocation;
        } else {
            return strategy.currentAllocation - strategy.targetAllocation;
        }
    }

    function _executeRebalance(bytes32 strategyId) internal {
        // Implementation needed
    }

    function _handlePerformanceFee(uint256 amount) internal {
        // Implementation needed
    }

    function _assessFees(
        uint256 gain
    ) internal view returns (uint256) {
        // Calculate management and performance fees
        uint256 duration = block.timestamp - lastReport;
        uint256 managementFee = (totalDebt * duration * 100) / (SECS_PER_YEAR * MAX_BPS);
        uint256 performanceFee = (gain * 1000) / MAX_BPS; // 10% performance fee
        
        return managementFee + performanceFee;
    }

    function _calculateLockedProfit() internal view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - lastReport) * MAX_BPS / LOCKED_PROFIT_DECAY;
        if (lockedFundsRatio >= MAX_BPS) return 0;
        return lockedProfit * (MAX_BPS - lockedFundsRatio) / MAX_BPS;
    }

    function _calculateShares(
        bytes32 vaultId,
        uint256 amount
    ) internal view returns (uint256) {
        // Implementation needed
        return amount;
    }

    function _calculateWithdrawAmount(
        bytes32 vaultId,
        uint256 shares
    ) internal view returns (uint256) {
        // Implementation needed
        return shares;
    }

    function _calculatePerformanceFee(
        bytes32 vaultId,
        uint256 amount
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _checkRebalance(
        address asset
    ) internal {
        AssetAllocation storage allocation = assetAllocations[asset];
        uint256 currentWeight = _getCurrentWeight(asset);
        
        if (currentWeight < allocation.minWeight || currentWeight > allocation.maxWeight) {
            // Trigger rebalance
            _rebalanceAsset(asset);
        }
    }

    function _getCurrentWeight(
        address asset
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _rebalanceAsset(
        address asset
    ) internal {
        // Implementation needed
    }

    // View functions
    function getStrategyInfo(
        bytes32 strategyId
    ) external view returns (VaultStrategy memory) {
        return strategies[strategyId];
    }

    function getPositionInfo(
        address asset,
        bytes32 strategyId
    ) external view returns (AssetPosition memory) {
        return assetPositions[asset][strategyId];
    }

    function getRiskParameters(
        bytes32 strategyId
    ) external view returns (RiskParameters memory) {
        return riskParams[strategyId];
    }

    function calculateStrategyValue(
        bytes32 strategyId
    ) external view returns (uint256 totalValue, uint256 profitLoss) {
        // Implementation needed
        return (0, 0);
    }

    function getStrategy(
        address strategy
    ) external view returns (VaultStrategy memory) {
        return strategies[strategy];
    }

    function getStrategyParams(
        address strategy
    ) external view returns (StrategyParams memory) {
        return strategyParams[strategy];
    }

    function getWithdrawalQueue(
        bytes32 queueId
    ) external view returns (WithdrawalQueue memory) {
        return withdrawalQueues[queueId];
    }

    function estimateAvailableAssets() external view returns (uint256) {
        return ikigaiToken.balanceOf(address(this)) - _calculateLockedProfit();
    }

    function getStrategyList() external view returns (address[] memory) {
        // Implementation needed
        return new address[](0);
    }

    function getVaultConfig(
        bytes32 vaultId
    ) external view returns (VaultConfig memory) {
        return vaultConfigs[vaultId];
    }

    function getUserPosition(
        bytes32 vaultId,
        address user
    ) external view returns (UserPosition memory) {
        return userPositions[vaultId][user];
    }

    function getAssetAllocation(
        address asset
    ) external view returns (AssetAllocation memory) {
        return assetAllocations[asset];
    }

    function isAssetSupported(
        address asset
    ) external view returns (bool) {
        return supportedAssets[asset];
    }
} 