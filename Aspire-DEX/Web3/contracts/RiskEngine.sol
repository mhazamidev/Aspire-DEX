// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IOracleHub.sol";
import "./PoolStorage.sol";

contract RiskEngine is AccessControl {
    bytes32 public constant RISK_ADMIN = keccak256("RISK_ADMIN");

    uint256 private constant PRECISION = 1e18;
    uint256 private constant RAY       = 1e27;

    IOracleHub  public immutable oracle;
    PoolStorage public immutable poolStorage;

    mapping(address => AssetConfig) private _assetConfigs;
    address[] public supportedAssets;

    struct AssetConfig {
        uint256 ltv;                  // max borrow ratio (0.75e18 = 75%)
        uint256 liquidationThreshold; // collateral value for HF calc (0.80e18 = 80%)
        uint256 liquidationBonus;     // 1.05e18 = 5% bonus to liquidators
        uint256 supplyCap;            // max total deposits (0 = uncapped)
        uint256 borrowCap;            // max total borrows (0 = uncapped)
        bool    isActive;
        bool    isBorrowable;
    }

    error AssetAlreadyListed(address asset);
    error InvalidConfig(string reason);

    event AssetConfigured(address indexed asset, uint256 ltv, uint256 threshold);
    event AssetDeactivated(address indexed asset);

    constructor(address _oracle, address _poolStorage, address admin) {
        oracle      = IOracleHub(_oracle);
        poolStorage = PoolStorage(_poolStorage);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RISK_ADMIN,         admin);
    }

    // ── Health Factor ─────────────────────────────────────────────────────────
    //
    //   HF = Σ(collateral_i × price_i × liquidationThreshold_i)
    //        ─────────────────────────────────────────────────────
    //        Σ(debt_j × price_j)
    //
    //   HF >= 1e18 → safe;  HF < 1e18 → liquidatable

    function getHealthFactor(address user) external view returns (uint256) {
        uint256 totalCollateralUSD = _getTotalCollateralUSD(user);
        uint256 totalDebtUSD       = _getTotalDebtUSD(user);

        if (totalDebtUSD == 0)        return type(uint256).max;
        if (totalCollateralUSD == 0)  return 0;

        return (totalCollateralUSD * PRECISION) / totalDebtUSD;
    }

    function isLiquidatable(address user) external view returns (bool) {
        uint256 totalCollateralUSD = _getTotalCollateralUSD(user);
        uint256 totalDebtUSD       = _getTotalDebtUSD(user);
        if (totalDebtUSD == 0) return false;
        return (totalCollateralUSD * PRECISION) / totalDebtUSD < PRECISION;
    }

    function getUserTotalCollateralUSD(address user) external view returns (uint256) {
        return _getTotalCollateralUSD(user);
    }

    function getUserTotalDebtUSD(address user) external view returns (uint256) {
        return _getTotalDebtUSD(user);
    }

    function getAssetConfig(address asset) external view returns (AssetConfig memory) {
        return _assetConfigs[asset];
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function configureAsset(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 supplyCap,
        uint256 borrowCap,
        bool    isBorrowable
    ) external onlyRole(RISK_ADMIN) {
        if (ltv >= liquidationThreshold)
            revert InvalidConfig("LTV must be less than liquidation threshold");
        if (liquidationThreshold >= PRECISION)
            revert InvalidConfig("Threshold must be less than 100%");
        if (liquidationBonus < PRECISION)
            revert InvalidConfig("Bonus must be >= 1.0");

        bool isNew = !_assetConfigs[asset].isActive;
        _assetConfigs[asset] = AssetConfig({
            ltv:                  ltv,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus:     liquidationBonus,
            supplyCap:            supplyCap,
            borrowCap:            borrowCap,
            isActive:             true,
            isBorrowable:         isBorrowable
        });

        if (isNew) supportedAssets.push(asset);
        emit AssetConfigured(asset, ltv, liquidationThreshold);
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _getTotalCollateralUSD(address user) internal view returns (uint256 total) {
        uint256 len = supportedAssets.length;
        for (uint256 i; i < len; ++i) {
            address asset       = supportedAssets[i];
            AssetConfig storage cfg = _assetConfigs[asset];
            if (!cfg.isActive) continue;

            PoolStorage.AssetState memory state = poolStorage.getStateView(asset);
            uint256 shares  = poolStorage.getUserSupplyShares(user, asset);
            if (shares == 0) continue;

            uint256 amount  = (shares * state.supplyIndex) / RAY;
            uint256 price   = oracle.getPriceSafe(asset);

            // Weight collateral by liquidationThreshold (not LTV — that's for borrow capacity)
            total += (amount * price * cfg.liquidationThreshold) / (PRECISION * PRECISION);
        }
    }

    function _getTotalDebtUSD(address user) internal view returns (uint256 total) {
        uint256 len = supportedAssets.length;
        for (uint256 i; i < len; ++i) {
            address asset = supportedAssets[i];
            if (!_assetConfigs[asset].isActive) continue;

            PoolStorage.AssetState memory state = poolStorage.getStateView(asset);
            uint256 shares = poolStorage.getUserDebtShares(user, asset);
            if (shares == 0) continue;

            uint256 amount = (shares * state.borrowIndex) / RAY;
            uint256 price  = oracle.getPriceSafe(asset);
            total += (amount * price) / PRECISION;
        }
    }
}