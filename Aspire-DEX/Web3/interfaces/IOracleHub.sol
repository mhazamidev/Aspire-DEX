interface IOracleHub {
    function getPrice(address asset) external view returns (uint256 price, uint256 updatedAt);
    function getPriceSafe(address asset) external view returns (uint256 price);
    function getTWAP(address pairAddress, uint32 period) external view returns (uint256);
}