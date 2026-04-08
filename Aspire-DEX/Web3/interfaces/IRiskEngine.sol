interface IRiskEngine {
    struct AssetConfig {
        uint256 ltv;                  // max borrow ratio (1e18 = 100%)
        uint256 liquidationThreshold; // health factor trigger (1e18 = 100%)
        uint256 liquidationBonus;     // liquidator bonus (e.g. 1.05e18 = 5%)
        bool    isActive;
        bool    isBorrowable;
    }

    function getHealthFactor(address user) external view returns (uint256);
    function getAssetConfig(address asset) external view returns (AssetConfig memory);
    function isLiquidatable(address user) external view returns (bool);
    function getUserTotalCollateralUSD(address user) external view returns (uint256);
    function getUserTotalDebtUSD(address user) external view returns (uint256);
}