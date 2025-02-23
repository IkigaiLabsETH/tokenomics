// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiEscrowExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ESCROW_MANAGER = keccak256("ESCROW_MANAGER");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct Escrow {
        address seller;           // Seller address
        address buyer;            // Buyer address
        uint256 amount;          // Escrow amount
        uint256 releaseTime;     // Release timestamp
        EscrowStatus status;     // Current status
        bool isDisputed;         // Dispute status
    }

    struct EscrowConfig {
        uint256 lockPeriod;      // Lock duration
        uint256 disputePeriod;   // Dispute window
        uint256 fee;             // Escrow fee
        uint256 minAmount;       // Minimum amount
        bool requiresApproval;   // Approval required
    }

    struct DisputeDetails {
        address initiator;       // Dispute initiator
        string reason;           // Dispute reason
        uint256 timestamp;       // Initiation time
        bool resolved;           // Resolution status
        bytes32 resolution;      // Resolution hash
    }

    enum EscrowStatus {
        PENDING,
        ACTIVE,
        RELEASED,
        REFUNDED,
        DISPUTED
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => Escrow) public escrows;
    mapping(bytes32 => EscrowConfig) public escrowConfigs;
    mapping(bytes32 => DisputeDetails) public disputes;
    mapping(address => bool) public trustedParties;
    
    uint256 public constant MIN_LOCK_PERIOD = 1 hours;
    uint256 public constant MAX_LOCK_PERIOD = 30 days;
    uint256 public constant MAX_FEE = 500; // 5%
    
    // Events
    event EscrowCreated(bytes32 indexed escrowId, address seller, address buyer);
    event EscrowReleased(bytes32 indexed escrowId, uint256 amount);
    event DisputeOpened(bytes32 indexed escrowId, address initiator);
    event DisputeResolved(bytes32 indexed escrowId, bytes32 resolution);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Escrow creation
    function createEscrow(
        bytes32 escrowId,
        address buyer,
        uint256 lockPeriod
    ) external payable nonReentrant whenNotPaused {
        require(!escrows[escrowId].seller != address(0), "Escrow exists");
        require(msg.value > 0, "Invalid amount");
        require(lockPeriod >= MIN_LOCK_PERIOD, "Lock period too short");
        require(lockPeriod <= MAX_LOCK_PERIOD, "Lock period too long");
        
        EscrowConfig storage config = escrowConfigs[escrowId];
        require(msg.value >= config.minAmount, "Below minimum");
        
        // Calculate fee
        uint256 fee = (msg.value * config.fee) / 10000;
        uint256 escrowAmount = msg.value - fee;
        
        // Create escrow
        escrows[escrowId] = Escrow({
            seller: msg.sender,
            buyer: buyer,
            amount: escrowAmount,
            releaseTime: block.timestamp + lockPeriod,
            status: EscrowStatus.ACTIVE,
            isDisputed: false
        });
        
        emit EscrowCreated(escrowId, msg.sender, buyer);
    }

    // Release funds
    function releaseEscrow(
        bytes32 escrowId
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        require(escrow.status == EscrowStatus.ACTIVE, "Invalid status");
        require(!escrow.isDisputed, "Disputed");
        require(block.timestamp >= escrow.releaseTime, "Lock period active");
        
        // Update status
        escrow.status = EscrowStatus.RELEASED;
        
        // Transfer funds
        payable(escrow.buyer).transfer(escrow.amount);
        
        emit EscrowReleased(escrowId, escrow.amount);
    }

    // Dispute handling
    function openDispute(
        bytes32 escrowId,
        string calldata reason
    ) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        require(
            msg.sender == escrow.seller || msg.sender == escrow.buyer,
            "Not authorized"
        );
        require(!escrow.isDisputed, "Already disputed");
        
        // Create dispute
        disputes[escrowId] = DisputeDetails({
            initiator: msg.sender,
            reason: reason,
            timestamp: block.timestamp,
            resolved: false,
            resolution: bytes32(0)
        });
        
        // Update escrow
        escrow.isDisputed = true;
        escrow.status = EscrowStatus.DISPUTED;
        
        emit DisputeOpened(escrowId, msg.sender);
    }

    // Dispute resolution
    function resolveDispute(
        bytes32 escrowId,
        address winner,
        bytes32 resolution
    ) external onlyRole(ESCROW_MANAGER) nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        DisputeDetails storage dispute = disputes[escrowId];
        
        require(escrow.isDisputed, "Not disputed");
        require(!dispute.resolved, "Already resolved");
        require(
            winner == escrow.seller || winner == escrow.buyer,
            "Invalid winner"
        );
        
        // Update dispute
        dispute.resolved = true;
        dispute.resolution = resolution;
        
        // Transfer funds to winner
        payable(winner).transfer(escrow.amount);
        
        // Update escrow
        escrow.status = EscrowStatus.RELEASED;
        
        emit DisputeResolved(escrowId, resolution);
    }

    // Internal functions
    function _validateParties(
        address seller,
        address buyer
    ) internal view returns (bool) {
        return trustedParties[seller] && trustedParties[buyer];
    }

    function _calculateFee(
        uint256 amount,
        uint256 feeRate
    ) internal pure returns (uint256) {
        return (amount * feeRate) / 10000;
    }

    // View functions
    function getEscrow(
        bytes32 escrowId
    ) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    function getEscrowConfig(
        bytes32 escrowId
    ) external view returns (EscrowConfig memory) {
        return escrowConfigs[escrowId];
    }

    function getDispute(
        bytes32 escrowId
    ) external view returns (DisputeDetails memory) {
        return disputes[escrowId];
    }

    function isTrustedParty(
        address party
    ) external view returns (bool) {
        return trustedParties[party];
    }
} 