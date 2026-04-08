// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  IPair
/// @notice Interface used by Router, OracleHub, and RiskEngine to interact
///         with AMM pairs without coupling to the concrete Pair implementation.
interface IPair {

    // ── Events ────────────────────────────────────────────────────────────────

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    event CircuitBreakerTripped(uint256 priceMove, uint256 threshold);
    event CircuitBreakerReset(address indexed by);
    event FeeUpdated(uint16 baseFee, uint16 volatilityFee);

    // ── Immutables ────────────────────────────────────────────────────────────

    function factory() external view returns (address);
    function token0()  external view returns (address);
    function token1()  external view returns (address);

    // ── State ──────────────────────────────────────────────────────────────────

    function baseFee()                  external view returns (uint16);
    function volatilityFee()            external view returns (uint16);
    function protocolFeeBps()           external view returns (uint16);
    function feeTo()                    external view returns (address);
    function circuitBreakerTripped()    external view returns (bool);
    function price0CumulativeLast()     external view returns (uint256);
    function price1CumulativeLast()     external view returns (uint256);
    function observationIndex()         external view returns (uint16);
    function observationCardinality()   external view returns (uint16);
    function observationCardinalityNext() external view returns (uint16);

    // ── Constants ─────────────────────────────────────────────────────────────

    function MINIMUM_LIQUIDITY()  external pure returns (uint256);
    function FEE_DENOMINATOR()    external pure returns (uint256);

    // ── Core views ────────────────────────────────────────────────────────────

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32  blockTimestampLast
        );

    /// @notice Time-weighted average price over [now - secondsAgo, now].
    /// @param  secondsAgo  Observation window (minimum 300 seconds).
    /// @return price0Avg   UQ112x112 average price of token0 in token1.
    /// @return price1Avg   UQ112x112 average price of token1 in token0.
    function observe(uint32 secondsAgo)
        external
        view
        returns (uint256 price0Avg, uint256 price1Avg);

    // ── ERC-20 (LP token) ─────────────────────────────────────────────────────

    function name()                              external view returns (string memory);
    function symbol()                            external view returns (string memory);
    function decimals()                          external view returns (uint8);
    function totalSupply()                       external view returns (uint256);
    function balanceOf(address owner)            external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value)   external returns (bool);
    function transfer(address to, uint256 value)       external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    // ── Mutating ──────────────────────────────────────────────────────────────

    /// @notice Add liquidity. Caller must transfer tokens first, then call mint.
    function mint(address to) external returns (uint256 liquidity);

    /// @notice Remove liquidity. Caller must transfer LP tokens to pair first, then call burn.
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /// @notice Execute a swap. Optimistic transfer — receiver gets tokens before
    ///         K is verified. Pass non-empty `data` for flash swaps.
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /// @notice Grow the TWAP ring buffer so longer windows become observable.
    function increaseObservationCardinality(uint16 next) external;

    // ── Factory-only ──────────────────────────────────────────────────────────

    function setFee(uint16 baseFee, uint16 volatilityFee) external;
    function resetCircuitBreaker() external;
}