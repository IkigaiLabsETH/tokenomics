// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/core/IIkigaiToken.sol";
import "../libraries/Constants.sol";
import "../libraries/Types.sol";

contract IkigaiToken is ERC20, Ownable, IIkigaiToken {
    // ... rest of the contract
} 