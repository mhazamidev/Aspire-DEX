// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Jump-rate IRM with smoothed transition at kink to prevent cliff instability
contract InterestRateModel {
    uint256 private constant PRECISION         = 1e18;
    uint256 private constant SECONDS_PER_YEAR  = 365 days;
    uint256 private constant SMOOTHING_RANGE   = 0.02e18; // 2% utilization smoothing band at kink

    uint256 public immutable baseRate;
    uint256 public immutable multiplierPerSecond;
    uint256 public immutable jumpMultiplierPerSecond;
    uint256 public immutable kink;
    uint256 public immutable kinkLow;   // kink - SMOOTHING_RANGE
    uint256 public immutable kinkHigh;  // kink + SMOOTHING_RANGE

    constructor(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) {
        require(kink_ <= PRECISION, "IRM: KINK_EXCEEDS_100");
        require(kink_ > SMOOTHING_RANGE, "IRM: KINK_TOO_LOW");

        baseRate              = baseRatePerYear / SECONDS_PER_YEAR;
        multiplierPerSecond   = multiplierPerYear / SECONDS_PER_YEAR;
        jumpMultiplierPerSecond = jumpMultiplierPerYear / SECONDS_PER_YEAR;
        kink                  = kink_;
        kinkLow               = kink_ - SMOOTHING_RANGE;
        kinkHigh              = kink_ + SMOOTHING_RANGE;
    }

    function getUtilizationRate(uint256 cash, uint256 borrows) public pure returns (uint256) {
        if (borrows == 0) return 0;
        uint256 total = cash + borrows;
        return (borrows * PRECISION) / total;
    }

    /// @notice Borrow rate per second at current utilization
    function getBorrowRatePerSecond(uint256 cash, uint256 borrows) public view returns (uint256) {
        uint256 util = getUtilizationRate(cash, borrows);
        return _borrowRateAtUtil(util);
    }

    function getBorrowRate(uint256 totalDebt, uint256 totalLiquidity) external view returns (uint256) {
        uint256 cash = totalLiquidity > totalDebt ? totalLiquidity - totalDebt : 0;
        return getBorrowRatePerSecond(cash, totalDebt) * SECONDS_PER_YEAR;
    }

    function getSupplyRate(
        uint256 totalDebt,
        uint256 totalLiquidity,
        uint256 reserveFactor
    ) external view returns (uint256) {
        uint256 cash         = totalLiquidity > totalDebt ? totalLiquidity - totalDebt : 0;
        uint256 util         = getUtilizationRate(cash, totalDebt);
        uint256 borrowRate   = _borrowRateAtUtil(util) * SECONDS_PER_YEAR;
        return (borrowRate * util * (PRECISION - reserveFactor)) / (PRECISION * PRECISION);
    }

    /// @dev Smooth cubic interpolation between normal and jump rate in [kinkLow, kinkHigh]
    function _borrowRateAtUtil(uint256 util) internal view returns (uint256) {
        if (util <= kinkLow) {
            return baseRate + (multiplierPerSecond * util) / PRECISION;
        }

        if (util >= kinkHigh) {
            // Pure jump region
            uint256 normalRateAtKink = baseRate + (multiplierPerSecond * kink) / PRECISION;
            return normalRateAtKink + (jumpMultiplierPerSecond * (util - kink)) / PRECISION;
        }

        // Smoothing band: cubic blend between normal and jump rate
        uint256 t             = ((util - kinkLow) * PRECISION) / (SMOOTHING_RANGE * 2);
        // Smoothstep: 3t² - 2t³
        uint256 t2            = (t * t) / PRECISION;
        uint256 smooth        = (3 * t2 - (2 * t2 * t) / PRECISION);

        uint256 normalRate    = baseRate + (multiplierPerSecond * util) / PRECISION;
        uint256 jumpRate      = baseRate + (multiplierPerSecond * kink) / PRECISION
                                + (jumpMultiplierPerSecond * (util - kink)) / PRECISION;

        return normalRate + (smooth * (jumpRate - normalRate)) / PRECISION;
    }
}