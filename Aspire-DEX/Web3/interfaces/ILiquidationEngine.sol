interface ILiquidationEngine {
    event Liquidation(
        address indexed liquidator,
        address indexed borrower,
        address indexed debtAsset,
        address collateralAsset,
        uint256 debtCovered,
        uint256 collateralSeized,
        uint256 bonus
    );

    function liquidate(
        address borrower,
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,    // pass type(uint256).max for full liquidation
        bool    receiveAToken   // true = receive aToken, false = underlying
    ) external;

    function getMaxLiquidatableDebt(
        address borrower,
        address debtAsset
    ) external view returns (uint256);
}