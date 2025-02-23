// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IIkigaiRewards.sol";
import "./interfaces/IIkigaiTreasury.sol";
import "./interfaces/IIkigaiNFT.sol";

/// @title IkigaiController - Coordinates protocol-wide actions and emergency controls
contract IkigaiController is Initializable, OwnableUpgradeable, Pausable {
    // --- State Variables ---
    IIkigaiRewards public rewards;
    IIkigaiTreasury public treasury;
    IIkigaiNFT public nft;
    
    bool public emergencyMode;
    mapping(address => bool) public emergencyAdmins;

    // --- Events ---
    event EmergencyModeActivated(bool enabled);
    event ContractsPaused(bool paused);
    event EmergencyAdminUpdated(address admin, bool status);
    event RewardRateAdjusted(uint256 newRate);

    /// @notice Initialize the controller
    function initialize(
        address _rewards,
        address _treasury,
        address _nft
    ) public initializer {
        __Ownable_init();
        
        rewards = IIkigaiRewards(_rewards);
        treasury = IIkigaiTreasury(_treasury);
        nft = IIkigaiNFT(_nft);
        
        emergencyAdmins[msg.sender] = true;
    }

    // --- Modifiers ---
    modifier onlyEmergencyAdmin() {
        require(emergencyAdmins[msg.sender], "Not emergency admin");
        _;
    }

    // --- Emergency Controls ---

    /// @notice Activate emergency mode across all contracts
    function activateEmergencyMode(bool enabled) external onlyEmergencyAdmin {
        emergencyMode = enabled;
        
        if (enabled) {
            _pause();
        } else {
            _unpause();
        }
        
        emit EmergencyModeActivated(enabled);
        emit ContractsPaused(enabled);
    }

    /// @notice Update emergency admin status
    function updateEmergencyAdmin(address admin, bool status) external onlyOwner {
        emergencyAdmins[admin] = status;
        emit EmergencyAdminUpdated(admin, status);
    }

    // --- Protocol Management ---

    /// @notice Adjust reward rate based on market conditions
    function adjustRewardRate() external onlyOwner {
        // Implement reward rate adjustment logic
        // This could consider:
        // - Current treasury balance
        // - Staking participation
        // - Market conditions
        emit RewardRateAdjusted(0); // Add actual rate
    }

    /// @notice Get protocol-wide stats
    function getProtocolStats() external view returns (
        uint256 totalStaked,
        uint256 totalRewardsDistributed,
        uint256 treasuryBalance,
        uint256 liquidityRatio
    ) {
        // Implement stats aggregation
        return (0, 0, 0, 0); // Add actual values
    }
} 