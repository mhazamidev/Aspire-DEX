// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracleHub {
    function getPrice(address asset) external view returns (uint256 price, uint256 updatedAt);
    function getPriceSafe(address asset) external view returns (uint256 price);
    function getTWAP(address pairAddress, uint32 period) external view returns (uint256);
}