// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract IkigaiTokenV2 is ERC20, ReentrancyGuard, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens
    uint256 public constant DAILY_EMISSION_CAP = 684_931_506 * 10**18; // ~250M per year
    
    mapping(address => uint256) public lastMintTimestamp;
    mapping(address => uint256) public dailyMintedAmount;
    
    event EmissionRateUpdated(uint256 newDailyRate);
    event MintingPaused(address indexed pauser);
    event MintingUnpaused(address indexed pauser);

    constructor() ERC20("Ikigai V2", "IKIGAI-V2") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
        nonReentrant 
    {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        
        // Reset daily minted amount if it's a new day
        if (block.timestamp >= lastMintTimestamp[to] + 1 days) {
            dailyMintedAmount[to] = 0;
        }
        
        require(
            dailyMintedAmount[to] + amount <= DAILY_EMISSION_CAP,
            "Exceeds daily emission cap"
        );

        dailyMintedAmount[to] += amount;
        lastMintTimestamp[to] = block.timestamp;
        
        _mint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        emit MintingPaused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        emit MintingUnpaused(msg.sender);
    }
} 