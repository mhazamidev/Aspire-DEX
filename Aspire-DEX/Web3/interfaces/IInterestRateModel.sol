interface IInterestRateModel {
    function getBorrowRate(uint256 totalDebt, uint256 totalLiquidity) external view returns (uint256);
    function getSupplyRate(uint256 totalDebt, uint256 totalLiquidity, uint256 reserveFactor) external view returns (uint256);
    function getUtilizationRate(uint256 totalDebt, uint256 totalLiquidity) external view returns (uint256);
}