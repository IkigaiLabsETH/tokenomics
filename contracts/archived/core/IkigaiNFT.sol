// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/core/IIkigaiNFT.sol";
import "../interfaces/core/IIkigaiToken.sol";
import "./IkigaiRewards.sol";

contract IkigaiNFT is IIkigaiNFT, Initializable, ERC721Upgradeable, OwnableUpgradeable, ReentrancyGuard, Pausable {
    // ... existing contract implementation with updated imports ...
    // The rest of the contract remains largely the same, just organized with interfaces
} 