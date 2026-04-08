// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IPair.sol";

contract OracleHub is AccessControl {
    bytes32 public constant ORACLE_ADMIN = keccak256("ORACLE_ADMIN");

    uint256 private constant PRECISION           = 1e18;
    uint256 private constant MAX_PRICE_DEVIATION = 0.03e18; // 3% TWAP vs Chainlink
    uint32  private constant TWAP_PERIOD         = 1800;    // 30-minute window

    struct OracleConfig {
        AggregatorV3Interface chainlinkFeed;
        address               twapPair;       // AMM Pair address for TWAP
        address               twapBaseToken;  // which token is the "base" in the pair
        uint256               staleness;      // max age of Chainlink price in seconds
        uint8                 feedDecimals;
        bool                  active;
    }

    mapping(address => OracleConfig) public configs;

    error NoPriceFeed(address asset);
    error StaleChainlinkPrice(address asset, uint256 updatedAt);
    error NegativePrice(address asset);
    error PriceManipulationDetected(address asset, uint256 twap, uint256 spot);
    error TWAPPeriodTooShort();

    event OracleConfigured(address indexed asset, address feed, address pair);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ADMIN,       admin);
    }

    function configureOracle(
        address asset,
        address chainlinkFeed,
        address twapPair,
        address twapBaseToken,
        uint256 staleness
    ) external onlyRole(ORACLE_ADMIN) {
        AggregatorV3Interface feed = AggregatorV3Interface(chainlinkFeed);
        configs[asset] = OracleConfig({
            chainlinkFeed:  feed,
            twapPair:       twapPair,
            twapBaseToken:  twapBaseToken,
            staleness:      staleness,
            feedDecimals:   feed.decimals(),
            active:         true
        });
        emit OracleConfigured(asset, chainlinkFeed, twapPair);
    }

    // Primary price — Chainlink with TWAP cross-validation
    function getPriceSafe(address asset) external view returns (uint256 price) {
        OracleConfig memory cfg = configs[asset];
        if (!cfg.active) revert NoPriceFeed(asset);

        uint256 chainlinkPrice = _getChainlinkPrice(cfg);

        // If TWAP pair is configured, cross-validate against TWAP
        if (cfg.twapPair != address(0)) {
            uint256 twapPrice = _getTWAPPrice(cfg);
            uint256 deviation = _deviation(chainlinkPrice, twapPrice);
            if (deviation > MAX_PRICE_DEVIATION) {
                revert PriceManipulationDetected(asset, twapPrice, chainlinkPrice);
            }
        }

        return chainlinkPrice;
    }

    // Raw Chainlink (no TWAP guard) — use only in view/display contexts
    function getPrice(address asset) external view returns (uint256 price, uint256 updatedAt) {
        OracleConfig memory cfg = configs[asset];
        if (!cfg.active) revert NoPriceFeed(asset);
        price = _getChainlinkPrice(cfg);
        (, , , updatedAt, ) = cfg.chainlinkFeed.latestRoundData();
    }

    // Pure TWAP (for protocols that want on-chain price only)
    function getTWAP(address pairAddress, uint32 period) external view returns (uint256) {
        if (period < 300) revert TWAPPeriodTooShort(); // 5 min minimum
        (uint256 price0Avg, ) = IPair(pairAddress).observe(period);
        return (price0Avg * PRECISION) >> 112; // decode UQ112x112
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _getChainlinkPrice(OracleConfig memory cfg) internal view returns (uint256) {
        (
            uint80  roundId,
            int256  answer,
            ,
            uint256 updatedAt,
            uint80  answeredInRound
        ) = cfg.chainlinkFeed.latestRoundData();

        if (answer <= 0)                                revert NegativePrice(address(cfg.chainlinkFeed));
        if (block.timestamp - updatedAt > cfg.staleness) revert StaleChainlinkPrice(address(cfg.chainlinkFeed), updatedAt);
        require(answeredInRound >= roundId, "OracleHub: STALE_ROUND");

        uint256 raw = uint256(answer);
        // Normalize to 18 decimals
        return cfg.feedDecimals < 18
            ? raw * 10 ** (18 - cfg.feedDecimals)
            : raw / 10 ** (cfg.feedDecimals - 18);
    }

    function _getTWAPPrice(OracleConfig memory cfg) internal view returns (uint256) {
        (uint256 price0Avg, uint256 price1Avg) = IPair(cfg.twapPair).observe(TWAP_PERIOD);
        // Return correct directional price based on which token is the base
        address token0 = IPair(cfg.twapPair).token0();
        uint256 rawTwap = cfg.twapBaseToken == token0 ? price0Avg : price1Avg;
        return (rawTwap * PRECISION) >> 112;
    }

    function _deviation(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > b) return ((a - b) * PRECISION) / b;
        return ((b - a) * PRECISION) / a;
    }
}