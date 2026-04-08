// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRiskEngine.sol";
import "../interfaces/IOracleHub.sol";
import "./LendingPool.sol";
import "./PoolStorage.sol";

contract LiquidationEngine is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION        = 1e18;
    uint256 private constant MAX_LIQUIDATION  = 0.5e18; // max 50% of debt per call (close factor)
    uint256 private constant RAY              = 1e27;

    LendingPool  public immutable lendingPool;
    PoolStorage  public immutable poolStorage;
    IRiskEngine  public immutable riskEngine;
    IOracleHub   public immutable oracle;

    event Liquidation(
        address indexed liquidator,
        address indexed borrower,
        address indexed debtAsset,
        address          collateralAsset,
        uint256          debtCovered,
        uint256          collateralSeized,
        uint256          bonus
    );

    error UserNotLiquidatable(address user, uint256 healthFactor);
    error DebtExceedsMax(uint256 requested, uint256 maxAllowed);
    error InsufficientCollateral(uint256 seizable, uint256 needed);
    error SelfLiquidation();

    constructor(
        address _lendingPool,
        address _poolStorage,
        address _riskEngine,
        address _oracle
    ) {
        lendingPool = LendingPool(_lendingPool);
        poolStorage = PoolStorage(_poolStorage);
        riskEngine  = IRiskEngine(_riskEngine);
        oracle      = IOracleHub(_oracle);
    }

    function liquidate(
        address borrower,
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,
        bool    receiveUnderlying
    ) external nonReentrant {
        if (msg.sender == borrower) revert SelfLiquidation();

        // ── Step 1: Validate position is liquidatable ─────────────────────────
        lendingPool.accrueInterest(debtAsset);
        lendingPool.accrueInterest(collateralAsset);

        uint256 healthFactor = riskEngine.getHealthFactor(borrower);
        if (healthFactor >= PRECISION) revert UserNotLiquidatable(borrower, healthFactor);

        // ── Step 2: Apply close factor (max 50% of debt per liquidation) ──────
        uint256 totalDebt    = _getUserDebtAmount(borrower, debtAsset);
        uint256 maxDebtCover = (totalDebt * MAX_LIQUIDATION) / PRECISION;

        if (debtToCover == type(uint256).max) debtToCover = maxDebtCover;
        if (debtToCover > maxDebtCover)       revert DebtExceedsMax(debtToCover, maxDebtCover);

        // ── Step 3: Calculate collateral to seize (with bonus) ───────────────
        IRiskEngine.AssetConfig memory collateralCfg = riskEngine.getAssetConfig(collateralAsset);
        uint256 collateralToSeize = _calculateCollateralToSeize(
            debtAsset,
            collateralAsset,
            debtToCover,
            collateralCfg.liquidationBonus
        );

        // Ensure borrower has enough collateral to seize
        uint256 borrowerCollateral = _getUserCollateralAmount(borrower, collateralAsset);
        if (collateralToSeize > borrowerCollateral) revert InsufficientCollateral(borrowerCollateral, collateralToSeize);

        // ── Step 4: Execute — pull debt from liquidator, push collateral ──────
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(lendingPool), debtToCover);
        _burnDebt(borrower, debtAsset, debtToCover);
        _seizeCollateral(borrower, msg.sender, collateralAsset, collateralToSeize, receiveUnderlying);

        // ── Step 5: Bad debt check — if HF still < 1 but no collateral left ──
        // Protocol socializes bad debt rather than leaving it unresolved
        _handleBadDebt(borrower, debtAsset, collateralAsset);

        emit Liquidation(
            msg.sender,
            borrower,
            debtAsset,
            collateralAsset,
            debtToCover,
            collateralToSeize,
            collateralCfg.liquidationBonus
        );
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _calculateCollateralToSeize(
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,
        uint256 liquidationBonus
    ) internal view returns (uint256) {
        uint256 debtPrice       = oracle.getPriceSafe(debtAsset);
        uint256 collateralPrice = oracle.getPriceSafe(collateralAsset);

        // collateralToSeize = (debtToCover × debtPrice × bonus) / collateralPrice
        return (debtToCover * debtPrice * liquidationBonus) / (collateralPrice * PRECISION);
    }

    function _getUserDebtAmount(address user, address asset) internal view returns (uint256) {
        PoolStorage.AssetState memory state = poolStorage.getStateView(asset);
        uint256 debtShares = poolStorage.getUserDebtShares(user, asset);
        return (debtShares * state.borrowIndex) / RAY;
    }

    function _getUserCollateralAmount(address user, address asset) internal view returns (uint256) {
        PoolStorage.AssetState memory state = poolStorage.getStateView(asset);
        uint256 supplyShares = poolStorage.getUserSupplyShares(user, asset);
        return (supplyShares * state.supplyIndex) / RAY;
    }

    function _burnDebt(address borrower, address asset, uint256 amount) internal {
        // Delegates to LendingPool repay logic (updates PoolStorage internally)
        lendingPool.repay(asset, amount, borrower);
    }

    function _seizeCollateral(
        address borrower,
        address liquidator,
        address asset,
        uint256 amount,
        bool    receiveUnderlying
    ) internal {
        PoolStorage.AssetState memory state = poolStorage.getStateView(asset);
        uint256 sharesToSeize = (amount * RAY) / state.supplyIndex;

        poolStorage.removeUserSupply(borrower, asset, uint128(sharesToSeize));

        if (receiveUnderlying) {
            IERC20(asset).safeTransfer(liquidator, amount);
        } else {
            // Transfer supply shares (aToken equivalent)
            poolStorage.addUserSupply(liquidator, asset, uint128(sharesToSeize));
        }
    }

    function _handleBadDebt(address borrower, address debtAsset, address collateralAsset) internal {
        uint256 remainingCollateral = _getUserCollateralAmount(borrower, collateralAsset);
        if (remainingCollateral > 0) return; // collateral remains, no bad debt

        uint256 remainingDebt = _getUserDebtAmount(borrower, debtAsset);
        if (remainingDebt == 0) return;

        // Socialize: write off remaining debt against the protocol reserve
        // This prevents phantom debt from accumulating in the system
        poolStorage.writeOffDebt(borrower, debtAsset, remainingDebt);
    }

    function getMaxLiquidatableDebt(
        address borrower,
        address debtAsset
    ) external view returns (uint256) {
        uint256 totalDebt = _getUserDebtAmount(borrower, debtAsset);
        return (totalDebt * MAX_LIQUIDATION) / PRECISION;
    }
}