// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIkigaiMarketplace {
    // Events
    event ListingCreated(uint256 indexed tokenId, address seller, uint256 price);
    event ListingCancelled(uint256 indexed tokenId);
    event Sale(uint256 indexed tokenId, address seller, address buyer, uint256 price);
    
    // View functions
    function getListing(uint256 tokenId) external view returns (
        address seller,
        uint256 price,
        bool active
    );
    
    // State-changing functions
    function createListing(uint256 tokenId, uint256 price) external;
    function cancelListing(uint256 tokenId) external;
    function buyToken(uint256 tokenId) external payable;
} 