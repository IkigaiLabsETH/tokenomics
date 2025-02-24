// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IBuybackEngine.sol";

contract IkigaiV2 is ERC20, ERC20Burnable, Pausable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Buyback integration
    IBuybackEngine public buybackEngine;

    // Transfer limits
    uint256 public constant MAX_TRANSFER = 1_000_000 * 10**18; // 1M tokens
    uint256 public constant TRANSFER_COOLDOWN = 1 minutes;
    mapping(address => uint256) public lastTransferTime;

    // Buyback parameters
    uint256 public constant BUYBACK_TAX = 100; // 1% tax on transfers
    uint256 public constant MIN_BUYBACK_AMOUNT = 1000 * 10**18; // 1000 tokens
    bool public buybackEnabled = true;

    // Events
    event BuybackCollected(uint256 amount);
    event BuybackEngineUpdated(address indexed newEngine);
    event TransferLimitUpdated(uint256 newLimit);
    event FeeExemptionUpdated(address indexed account, bool exempt);
    event EmergencyRecovery(address indexed token, uint256 amount);

    // Update transfer tax parameters
    struct TaxTier {
        uint256 threshold;
        uint256 rate;
    }

    TaxTier[] public transferTaxTiers = [
        TaxTier(100_000 * 10**18, 200),  // 2% for <100K
        TaxTier(500_000 * 10**18, 300),  // 3% for 100K-500K
        TaxTier(type(uint256).max, 500)  // 5% for >500K
    ];

    // Add whitelist for fee exemption
    mapping(address => bool) public feeExempt;

    function getTransferTax(uint256 amount) public view returns (uint256) {
        for (uint i = 0; i < transferTaxTiers.length; i++) {
            if (amount <= transferTaxTiers[i].threshold) {
                return transferTaxTiers[i].rate;
            }
        }
        return transferTaxTiers[transferTaxTiers.length - 1].rate;
    }

    constructor(
        address _admin,
        address _buybackEngine
    ) ERC20("Ikigai V2", "IKIGAI") {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MINTER_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _admin);
        
        buybackEngine = IBuybackEngine(_buybackEngine);
    }

    // Minting function
    function mint(address to, uint256 amount) external {
        require(hasRole(MINTER_ROLE, msg.sender), "Must have minter role");
        _mint(to, amount);
    }

    // Update transfer function to use tiered tax
    function transfer(
        address recipient, 
        uint256 amount
    ) public virtual override returns (bool) {
        require(amount <= MAX_TRANSFER, "Transfer exceeds limit");
        require(
            block.timestamp >= lastTransferTime[msg.sender] + TRANSFER_COOLDOWN || 
            feeExempt[msg.sender],
            "Transfer cooldown active"
        );

        // Skip buyback for exempt addresses
        if (feeExempt[msg.sender] || feeExempt[recipient]) {
            bool success = super.transfer(recipient, amount);
            if (success) {
                lastTransferTime[msg.sender] = block.timestamp;
            }
            return success;
        }

        // Calculate buyback amount using tiered tax
        uint256 taxRate = getTransferTax(amount);
        uint256 buybackAmount = (amount * taxRate) / 10000;
        uint256 transferAmount = amount - buybackAmount;

        // Process buyback if enabled and amount is sufficient
        if (buybackEnabled && buybackAmount > 0) {
            // Transfer buyback amount to buyback engine
            super.transfer(address(buybackEngine), buybackAmount);
            
            // Notify buyback engine
            buybackEngine.collectRevenue(
                keccak256("TRANSFER_FEES"),
                buybackAmount
            );
            
            emit BuybackCollected(buybackAmount);
        }

        // Process main transfer
        bool success = super.transfer(recipient, transferAmount);
        if (success) {
            lastTransferTime[msg.sender] = block.timestamp;
        }
        return success;
    }

    // Update transferFrom to use tiered tax
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(amount <= MAX_TRANSFER, "Transfer exceeds limit");
        require(
            block.timestamp >= lastTransferTime[sender] + TRANSFER_COOLDOWN,
            "Transfer cooldown active"
        );

        // Calculate buyback amount using tiered tax
        uint256 taxRate = getTransferTax(amount);
        uint256 buybackAmount = (amount * taxRate) / 10000;
        uint256 transferAmount = amount - buybackAmount;

        // Process buyback if enabled and amount is sufficient
        if (buybackEnabled && buybackAmount > 0) {
            // Transfer buyback amount to buyback engine
            super.transferFrom(sender, address(buybackEngine), buybackAmount);
            
            // Notify buyback engine
            buybackEngine.collectRevenue(
                keccak256("TRANSFER_FEES"),
                buybackAmount
            );
            
            emit BuybackCollected(buybackAmount);
        }

        // Process main transfer
        bool success = super.transferFrom(sender, recipient, transferAmount);
        if (success) {
            lastTransferTime[sender] = block.timestamp;
        }
        return success;
    }

    // Admin functions
    function updateBuybackEngine(address newEngine) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Must be admin");
        require(newEngine != address(0), "Invalid address");
        buybackEngine = IBuybackEngine(newEngine);
        emit BuybackEngineUpdated(newEngine);
    }

    function toggleBuyback(bool enabled) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Must be operator");
        buybackEnabled = enabled;
    }

    function pause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Must be operator");
        _pause();
    }

    function unpause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Must be operator");
        _unpause();
    }

    // Required overrides
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    // The following functions are overrides required by Solidity
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Add function to update tax tiers
    function updateTaxTiers(
        uint256[] memory thresholds,
        uint256[] memory rates
    ) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Must be operator");
        require(thresholds.length == rates.length, "Array length mismatch");
        require(thresholds.length > 0, "Empty arrays");
        
        // Clear existing tiers
        delete transferTaxTiers;
        
        // Add new tiers
        for (uint i = 0; i < thresholds.length; i++) {
            transferTaxTiers.push(TaxTier({
                threshold: thresholds[i],
                rate: rates[i]
            }));
        }
    }

    // Add function to update fee exemption
    function setFeeExemption(address account, bool exempt) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Must be operator");
        feeExempt[account] = exempt;
        emit FeeExemptionUpdated(account, exempt);
    }

    // Add emergency recovery function
    function emergencyTokenRecovery(address token, uint256 amount) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Must be admin");
        require(paused(), "Contract not paused");
        
        if (token == address(this)) {
            // For recovering own tokens
            _transfer(address(this), msg.sender, amount);
        } else {
            // For recovering other tokens
            IERC20(token).transfer(msg.sender, amount);
        }
        
        emit EmergencyRecovery(token, amount);
    }
}