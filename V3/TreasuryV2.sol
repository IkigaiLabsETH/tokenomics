// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TreasuryV2 is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    // Token references
    IERC20 public immutable ikigaiToken;
    IERC20 public immutable stablecoin;

    // Treasury parameters
    uint256 public constant TARGET_LIQUIDITY_RATIO = 2000; // 20% of treasury
    uint256 public constant REBALANCING_THRESHOLD = 500;   // 5% threshold
    uint256 public constant MAX_SLIPPAGE = 100;           // 1% max slippage
    uint256 public constant MIN_LIQUIDITY = 1000 * 10**18; // 1,000 tokens

    // Distribution ratios (in basis points)
    uint256 public constant STAKING_SHARE = 5000;  // 50%
    uint256 public constant LIQUIDITY_SHARE = 3000; // 30%
    uint256 public constant OPERATIONS_SHARE = 1500; // 15%
    uint256 public constant BURN_SHARE = 500;       // 5%

    // Addresses
    address public stakingContract;
    address public liquidityPool;
    address public operationsWallet;
    address public burnAddress;

    // Treasury state
    uint256 public totalAssets;
    uint256 public liquidityBalance;
    uint256 public lastRebalance;

    // Events
    event RevenueDistributed(
        uint256 stakingAmount,
        uint256 liquidityAmount,
        uint256 operationsAmount,
        uint256 burnAmount
    );
    event LiquidityRebalanced(uint256 amount, bool added);
    event AddressesUpdated(
        address stakingContract,
        address liquidityPool,
        address operationsWallet
    );

    constructor(
        address _ikigaiToken,
        address _stablecoin,
        address _admin,
        address _stakingContract,
        address _liquidityPool,
        address _operationsWallet
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        stablecoin = IERC20(_stablecoin);
        stakingContract = _stakingContract;
        liquidityPool = _liquidityPool;
        operationsWallet = _operationsWallet;
        burnAddress = address(0xdead);

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _admin);
        _setupRole(REBALANCER_ROLE, _admin);

        lastRebalance = block.timestamp;
    }

    // Update critical addresses
    function updateAddresses(
        address _stakingContract,
        address _liquidityPool,
        address _operationsWallet
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        require(_stakingContract != address(0), "Invalid staking contract");
        require(_liquidityPool != address(0), "Invalid liquidity pool");
        require(_operationsWallet != address(0), "Invalid operations wallet");

        stakingContract = _stakingContract;
        liquidityPool = _liquidityPool;
        operationsWallet = _operationsWallet;

        emit AddressesUpdated(_stakingContract, _liquidityPool, _operationsWallet);
    }

    // Distribute revenue according to ratios
    function distributeRevenue() external nonReentrant whenNotPaused {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        
        uint256 balance = ikigaiToken.balanceOf(address(this));
        require(balance > 0, "No tokens to distribute");

        // Calculate shares
        uint256 stakingAmount = (balance * STAKING_SHARE) / 10000;
        uint256 liquidityAmount = (balance * LIQUIDITY_SHARE) / 10000;
        uint256 operationsAmount = (balance * OPERATIONS_SHARE) / 10000;
        uint256 burnAmount = (balance * BURN_SHARE) / 10000;

        // Transfer shares
        if (stakingAmount > 0) {
            ikigaiToken.safeTransfer(stakingContract, stakingAmount);
        }
        if (liquidityAmount > 0) {
            ikigaiToken.safeTransfer(liquidityPool, liquidityAmount);
        }
        if (operationsAmount > 0) {
            ikigaiToken.safeTransfer(operationsWallet, operationsAmount);
        }
        if (burnAmount > 0) {
            ikigaiToken.safeTransfer(burnAddress, burnAmount);
        }

        emit RevenueDistributed(
            stakingAmount,
            liquidityAmount,
            operationsAmount,
            burnAmount
        );
    }

    // Check if rebalancing is needed
    function needsRebalancing() public view returns (bool, bool) {
        uint256 currentRatio = (liquidityBalance * 10000) / totalAssets;
        
        if (currentRatio < TARGET_LIQUIDITY_RATIO - REBALANCING_THRESHOLD) {
            return (true, true); // Needs more liquidity
        }
        if (currentRatio > TARGET_LIQUIDITY_RATIO + REBALANCING_THRESHOLD) {
            return (true, false); // Needs less liquidity
        }
        
        return (false, false);
    }

    // Rebalance liquidity
    function rebalanceLiquidity() external nonReentrant whenNotPaused {
        require(hasRole(REBALANCER_ROLE, msg.sender), "Caller is not rebalancer");
        require(block.timestamp >= lastRebalance + 1 days, "Too soon to rebalance");

        (bool shouldRebalance, bool addLiquidity) = needsRebalancing();
        require(shouldRebalance, "No rebalancing needed");

        uint256 targetLiquidity = (totalAssets * TARGET_LIQUIDITY_RATIO) / 10000;
        uint256 difference = addLiquidity ? 
            targetLiquidity - liquidityBalance :
            liquidityBalance - targetLiquidity;

        require(difference >= MIN_LIQUIDITY, "Below minimum liquidity change");

        if (addLiquidity) {
            // Add liquidity logic here
            liquidityBalance += difference;
        } else {
            // Remove liquidity logic here
            liquidityBalance -= difference;
        }

        lastRebalance = block.timestamp;
        emit LiquidityRebalanced(difference, addLiquidity);
    }

    // Emergency functions
    function pause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        _pause();
    }

    function unpause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        _unpause();
    }

    // View functions
    function getTreasuryStats() external view returns (
        uint256 _totalAssets,
        uint256 _liquidityBalance,
        uint256 _liquidityRatio,
        uint256 _lastRebalance
    ) {
        _liquidityRatio = (liquidityBalance * 10000) / totalAssets;
        return (
            totalAssets,
            liquidityBalance,
            _liquidityRatio,
            lastRebalance
        );
    }
} 