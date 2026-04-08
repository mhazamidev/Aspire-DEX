// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IOracleHub.sol";
import "./Factory.sol";
import "./Pair.sol";

contract Router is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant MAX_ORACLE_DEVIATION = 0.03e18; // 3%
    uint256 private constant PRECISION            = 1e18;

    Factory    public immutable factory;
    IOracleHub public immutable oracle;

    error Expired(uint256 deadline, uint256 current);
    error InsufficientOutputAmount(uint256 got, uint256 min);
    error ExcessiveInputAmount(uint256 got, uint256 max);
    error OraclePriceDeviation(uint256 executionPrice, uint256 oraclePrice, uint256 deviation);
    error InvalidPath();
    error PairDoesNotExist(address tokenA, address tokenB);
    error CircuitBreakerActive(address pair);

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) revert Expired(deadline, block.timestamp);
        _;
    }

    constructor(address _factory, address _oracle) {
        factory = Factory(_factory);
        oracle  = IOracleHub(_oracle);
    }

    // ── Quote (view, no state change) ─────────────────────────────────────────

    function quoteExactInput(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            (uint112 r0, uint112 r1,) = _getPairReserves(path[i], path[i+1]);
            amounts[i+1] = _getAmountOut(amounts[i], r0, r1, path[i], path[i+1]);
        }
    }

    function quoteExactOutput(
        uint256 amountOut,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; --i) {
            (uint112 r0, uint112 r1,) = _getPairReserves(path[i-1], path[i]);
            amounts[i-1] = _getAmountIn(amounts[i], r0, r1, path[i-1], path[i]);
        }
    }

    // ── Execute ────────────────────────────────────────────────────────────────

    function swapExactTokensForTokens(
        uint256          amountIn,
        uint256          amountOutMin,
        address[] calldata path,
        address          to,
        uint256          deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        if (path.length < 2) revert InvalidPath();

        amounts = _computeAmounts(amountIn, path);

        uint256 amountOut = amounts[amounts.length - 1];
        if (amountOut < amountOutMin)
            revert InsufficientOutputAmount(amountOut, amountOutMin);

        // Oracle sanity: verify execution price is within tolerance
        _validateOraclePrice(path[0], path[path.length - 1], amountIn, amountOut);

        // Check no circuit breaker is active on any pair in path
        _validatePathCircuitBreakers(path);

        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            factory.getPair(path[0], path[1]),
            amounts[0]
        );
        _executeSwaps(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256          amountOut,
        uint256          amountInMax,
        address[] calldata path,
        address          to,
        uint256          deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        if (path.length < 2) revert InvalidPath();

        amounts = _computeAmountsForExact(amountOut, path);

        if (amounts[0] > amountInMax)
            revert ExcessiveInputAmount(amounts[0], amountInMax);

        _validateOraclePrice(path[0], path[path.length - 1], amounts[0], amountOut);
        _validatePathCircuitBreakers(path);

        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            factory.getPair(path[0], path[1]),
            amounts[0]
        );
        _executeSwaps(amounts, path, to);
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _validateOraclePrice(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal view {
        // Only validate if oracle has both feeds registered
        try oracle.getPriceSafe(tokenIn)  returns (uint256 priceIn)  {
        try oracle.getPriceSafe(tokenOut) returns (uint256 priceOut) {
            // Implied execution rate: amountOut/amountIn normalized by prices
            // executionPrice = (amountOut * priceOut) / (amountIn * priceIn) — should be ~1
            uint256 executionValue = (amountOut * priceOut) / PRECISION;
            uint256 inputValue     = (amountIn  * priceIn)  / PRECISION;

            if (inputValue == 0) return;
            uint256 executionPrice = (executionValue * PRECISION) / inputValue;

            uint256 deviation = executionPrice > PRECISION
                ? executionPrice - PRECISION
                : PRECISION - executionPrice;

            if (deviation > MAX_ORACLE_DEVIATION)
                revert OraclePriceDeviation(executionPrice, PRECISION, deviation);
        } catch {} } catch {} // oracle missing for one token → skip validation
    }

    function _validatePathCircuitBreakers(address[] calldata path) internal view {
        for (uint256 i; i < path.length - 1; ++i) {
            address pairAddr = factory.getPair(path[i], path[i+1]);
            if (Pair(pairAddr).circuitBreakerTripped())
                revert CircuitBreakerActive(pairAddr);
        }
    }

    function _executeSwaps(
        uint256[] memory amounts,
        address[] calldata path,
        address to
    ) internal {
        for (uint256 i; i < path.length - 1; ++i) {
            address pairAddr = factory.getPair(path[i], path[i+1]);
            Pair    pair     = Pair(pairAddr);

            bool    zeroForOne = path[i] < path[i+1];
            address nextTo     = i < path.length - 2
                ? factory.getPair(path[i+1], path[i+2])
                : to;

            (uint256 out0, uint256 out1) = zeroForOne
                ? (uint256(0), amounts[i+1])
                : (amounts[i+1], uint256(0));

            pair.swap(out0, out1, nextTo, new bytes(0));
        }
    }

    function _computeAmounts(uint256 amountIn, address[] calldata path)
        internal view returns (uint256[] memory amounts)
    {
        amounts    = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            (uint112 r0, uint112 r1,) = _getPairReserves(path[i], path[i+1]);
            amounts[i+1] = _getAmountOut(amounts[i], r0, r1, path[i], path[i+1]);
        }
    }

    function _computeAmountsForExact(uint256 amountOut, address[] calldata path)
        internal view returns (uint256[] memory amounts)
    {
        amounts                    = new uint256[](path.length);
        amounts[amounts.length-1]  = amountOut;
        for (uint256 i = path.length - 1; i > 0; --i) {
            (uint112 r0, uint112 r1,) = _getPairReserves(path[i-1], path[i]);
            amounts[i-1] = _getAmountIn(amounts[i], r0, r1, path[i-1], path[i]);
        }
    }

    function _getAmountOut(
        uint256 amountIn,
        uint112 r0, uint112 r1,
        address tokenIn, address tokenOut
    ) internal view returns (uint256) {
        address pairAddr = factory.getPair(tokenIn, tokenOut);
        Pair    pair     = Pair(pairAddr);
        uint256 fee      = uint256(pair.baseFee()) + uint256(pair.volatilityFee());

        bool zeroForOne = tokenIn < tokenOut;
        (uint256 rIn, uint256 rOut) = zeroForOne
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));

        uint256 amountInWithFee = amountIn * (Pair(pairAddr).FEE_DENOMINATOR() - fee);
        return (amountInWithFee * rOut) /
               (rIn * Pair(pairAddr).FEE_DENOMINATOR() + amountInWithFee);
    }

    function _getAmountIn(
        uint256 amountOut,
        uint112 r0, uint112 r1,
        address tokenIn, address tokenOut
    ) internal view returns (uint256) {
        address pairAddr = factory.getPair(tokenIn, tokenOut);
        Pair    pair     = Pair(pairAddr);
        uint256 fee      = uint256(pair.baseFee()) + uint256(pair.volatilityFee());
        uint256 feeDen   = pair.FEE_DENOMINATOR();

        bool zeroForOne = tokenIn < tokenOut;
        (uint256 rIn, uint256 rOut) = zeroForOne
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));

        return (rIn * amountOut * feeDen) /
               ((rOut - amountOut) * (feeDen - fee)) + 1;
    }

    function _getPairReserves(address tokenA, address tokenB)
        internal view returns (uint112 r0, uint112 r1, uint32 ts)
    {
        address pairAddr = factory.getPair(tokenA, tokenB);
        if (pairAddr == address(0)) revert PairDoesNotExist(tokenA, tokenB);
        return Pair(pairAddr).getReserves();
    }
}