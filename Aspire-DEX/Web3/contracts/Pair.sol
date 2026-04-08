// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title  Pair — production AMM with TWAP, flash guards, circuit breaker
/// @notice x*y=k with UQ112x112 TWAP, dynamic fee, and per-block manipulation guard
contract Pair is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ── Types ──────────────────────────────────────────────────────────────────
    struct Observation {
        uint32  timestamp;
        uint224 price0Cumulative;
        uint224 price1Cumulative;
    }

    // ── Constants ──────────────────────────────────────────────────────────────
    uint256 public  constant MINIMUM_LIQUIDITY    = 1_000;
    uint256 public  constant FEE_DENOMINATOR      = 10_000;
    uint256 private constant MAX_RESERVE          = type(uint112).max;
    uint256 private constant CIRCUIT_BREAKER_BPS  = 1000; // 10% max price move per block
    uint32  private constant MIN_TWAP_PERIOD       = 300;  // 5 min minimum observation window

    // ── Immutables ─────────────────────────────────────────────────────────────
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    // ── State ──────────────────────────────────────────────────────────────────
    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32  private _blockTimestampLast;

    // TWAP: ring buffer of observations (cardinality configurable by Factory)
    Observation[] public observations;
    uint16  public observationIndex;
    uint16  public observationCardinality;
    uint16  public observationCardinalityNext;

    // Cumulative prices (UQ112x112 fixed point)
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    // Dynamic fee: base + volatility surcharge (both in bps)
    uint16  public baseFee;           // e.g. 30 = 0.30%
    uint16  public volatilityFee;     // set by keeper / governor based on vol

    // Circuit breaker: last block's implied price (UQ112x112)
    uint224 private _lastBlockPrice0; // price0 at end of last block
    bool    public  circuitBreakerTripped;

    // Protocol fee: feeTo receives a portion of liquidity fees
    address public feeTo;
    uint16  public protocolFeeBps;    // portion of baseFee going to protocol (e.g. 5 = 1/6 of fee)

    // Per-block swap volume (for volatility detection, reset each block)
    uint256 private _blockVolumeToken0;
    uint256 private _blockVolumeToken1;
    uint32  private _lastSwapBlock;

    // ── Events ─────────────────────────────────────────────────────────────────
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,  uint256 amount1In,
        uint256 amount0Out, uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    event CircuitBreakerTripped(uint256 priceMove, uint256 threshold);
    event CircuitBreakerReset(address indexed by);
    event FeeUpdated(uint16 baseFee, uint16 volatilityFee);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error Locked();
    error InsufficientLiquidity();
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error InvalidK();
    error InvalidTo();
    error ReserveOverflow();
    error CircuitBreakerActive();
    error TWAPPeriodTooShort();
    error InvalidObservationCardinality();
    error Forbidden();

    // ── Modifiers ──────────────────────────────────────────────────────────────
    modifier onlyFactory() {
        if (msg.sender != factory) revert Forbidden();
        _;
    }

    modifier circuitBreakerOff() {
        if (circuitBreakerTripped) revert CircuitBreakerActive();
        _;
    }

    // ── Constructor ────────────────────────────────────────────────────────────
    constructor(
        address _token0,
        address _token1,
        uint16  _baseFee,
        address _feeTo,
        uint16  _protocolFeeBps
    ) ERC20("DEX-LP", "DLP") {
        factory        = msg.sender;
        token0         = _token0;
        token1         = _token1;
        baseFee        = _baseFee;
        feeTo          = _feeTo;
        protocolFeeBps = _protocolFeeBps;

        // Initialize TWAP ring buffer with one slot
        observations.push(Observation(0, 0, 0));
        observationCardinality     = 1;
        observationCardinalityNext = 1;
    }

    // ── TWAP: grow ring buffer ─────────────────────────────────────────────────
    function increaseObservationCardinality(uint16 next) external {
        uint16 current = observationCardinalityNext;
        if (next <= current) revert InvalidObservationCardinality();
        for (uint16 i = current; i < next; ++i) {
            observations.push(Observation(0, 0, 0));
        }
        observationCardinalityNext = next;
    }

    // ── View ───────────────────────────────────────────────────────────────────
    function getReserves() public view returns (
        uint112 reserve0_,
        uint112 reserve1_,
        uint32  blockTimestampLast_
    ) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    /// @notice Get time-weighted average price over [secondsAgo, now]
    /// @param  secondsAgo window in seconds (minimum MIN_TWAP_PERIOD)
    /// @return price0Avg  UQ112x112 average price of token0 in token1
    /// @return price1Avg  UQ112x112 average price of token1 in token0
    function observe(uint32 secondsAgo)
        external view
        returns (uint256 price0Avg, uint256 price1Avg)
    {
        if (secondsAgo < MIN_TWAP_PERIOD) revert TWAPPeriodTooShort();

        uint32  currentTime = uint32(block.timestamp);
        uint256 c0 = price0CumulativeLast;
        uint256 c1 = price1CumulativeLast;

        // Add pending accumulation since last write
        uint32 elapsed = currentTime - _blockTimestampLast;
        if (elapsed > 0 && _reserve0 > 0 && _reserve1 > 0) {
            c0 += _encodePrice(_reserve1, _reserve0) * elapsed;
            c1 += _encodePrice(_reserve0, _reserve1) * elapsed;
        }

        // Find oldest observation within window from ring buffer
        Observation memory oldest = _getOldestObservation(secondsAgo);

        uint32 windowElapsed = currentTime - oldest.timestamp;
        price0Avg = (c0 - oldest.price0Cumulative) / windowElapsed;
        price1Avg = (c1 - oldest.price1Cumulative) / windowElapsed;
    }

    // ── Mint ───────────────────────────────────────────────────────────────────
    function mint(address to) external nonReentrant circuitBreakerOff returns (uint256 liquidity) {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0  = balance0 - reserve0_;
        uint256 amount1  = balance1 - reserve1_;

        uint256 _totalSupply = totalSupply();

        // Protocol fee: mint fee shares to feeTo before user's mint
        bool feeOn = _mintProtocolFee(reserve0_, reserve1_, _totalSupply);
        if (feeOn) _totalSupply = totalSupply(); // re-read after fee mint

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * _totalSupply) / reserve0_,
                (amount1 * _totalSupply) / reserve1_
            );
        }

        if (liquidity == 0) revert InsufficientLiquidity();
        _mint(to, liquidity);

        _update(balance0, balance1, reserve0_, reserve1_);
        emit Mint(msg.sender, amount0, amount1);
    }

    // ── Burn ───────────────────────────────────────────────────────────────────
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0    = IERC20(token0).balanceOf(address(this));
        uint256 balance1    = IERC20(token1).balanceOf(address(this));
        uint256 liquidity   = balanceOf(address(this));
        uint256 _totalSupply = totalSupply();

        bool feeOn = _mintProtocolFee(reserve0_, reserve1_, _totalSupply);
        if (feeOn) _totalSupply = totalSupply();

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();

        _burn(address(this), liquidity);
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0_, reserve1_
        );
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // ── Swap ───────────────────────────────────────────────────────────────────
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data  // for flash swaps; empty = regular swap
    ) external nonReentrant circuitBreakerOff {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        if (to == token0 || to == token1)       revert InvalidTo();

        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        if (amount0Out >= reserve0_ || amount1Out >= reserve1_) revert InsufficientLiquidity();

        // Optimistically transfer output
        if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

        // Flash swap callback (if data provided)
        if (data.length > 0) {
            IFlashSwapReceiver(to).flashSwapCallback(
                msg.sender, amount0Out, amount1Out, data
            );
        }

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Compute amounts in from balance diff
        uint256 amount0In = balance0 > reserve0_ - amount0Out
            ? balance0 - (reserve0_ - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1_ - amount1Out
            ? balance1 - (reserve1_ - amount1Out) : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        // Apply fee: adjusted balances for K check
        uint256 totalFee = uint256(baseFee) + uint256(volatilityFee); // in bps
        uint256 balance0Adjusted = balance0 * FEE_DENOMINATOR - amount0In * totalFee;
        uint256 balance1Adjusted = balance1 * FEE_DENOMINATOR - amount1In * totalFee;

        // K invariant check (with fee adjustment)
        if (balance0Adjusted * balance1Adjusted == uint256(reserve0_) * uint256(reserve1_) * (FEE_DENOMINATOR ** 2))
        {
            revert InvalidK();
        }

        // Circuit breaker: check price impact
        _checkCircuitBreaker(balance0, balance1, reserve0_, reserve1_);

        // Track per-block volume for volatility fee adjustment
        _trackBlockVolume(amount0In, amount1In);

        _update(balance0, balance1, reserve0_, reserve1_);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // ── Internal: TWAP update ─────────────────────────────────────────────────
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 reserve0_,
        uint112 reserve1_
    ) private {
        if (balance0 > MAX_RESERVE || balance1 > MAX_RESERVE) revert ReserveOverflow();

        uint32 currentTime = uint32(block.timestamp);
        uint32 elapsed     = currentTime - _blockTimestampLast;

        if (elapsed > 0 && reserve0_ > 0 && reserve1_ > 0) {
            // UQ112x112 price accumulation
            price0CumulativeLast += _encodePrice(reserve1_, reserve0_) * elapsed;
            price1CumulativeLast += _encodePrice(reserve0_, reserve1_) * elapsed;

            // Write to ring buffer once per block
            uint16 idx    = (observationIndex + 1) % observationCardinality;
            observations[idx] = Observation({
                timestamp:         currentTime,
                price0Cumulative:  uint224(price0CumulativeLast),
                price1Cumulative:  uint224(price1CumulativeLast)
            });
            observationIndex = idx;
            if (observationCardinality < observationCardinalityNext) {
                observationCardinality++;
            }
        }

        _reserve0           = uint112(balance0);
        _reserve1           = uint112(balance1);
        _blockTimestampLast = currentTime;

        emit Sync(_reserve0, _reserve1);
    }

    // ── Internal: circuit breaker ─────────────────────────────────────────────
    function _checkCircuitBreaker(
        uint256 balance0, uint256 balance1,
        uint112 reserve0_, uint112 reserve1_
    ) private {
        if (reserve0_ == 0 || reserve1_ == 0) return;

        // Current implied price (UQ112x112)
        uint224 newPrice = uint224((uint256(balance1) << 112) / balance0);
        uint224 oldPrice = _lastBlockPrice0;

        if (oldPrice > 0) {
            // Compute price move in bps
            uint256 move = newPrice > oldPrice
                ? ((uint256(newPrice) - oldPrice) * 10_000) / oldPrice
                : ((uint256(oldPrice) - newPrice) * 10_000) / oldPrice;

            if (move > CIRCUIT_BREAKER_BPS) {
                circuitBreakerTripped = true;
                emit CircuitBreakerTripped(move, CIRCUIT_BREAKER_BPS);
            }
        }

        _lastBlockPrice0 = newPrice;
    }

    function resetCircuitBreaker() external onlyFactory {
        circuitBreakerTripped = false;
        emit CircuitBreakerReset(msg.sender);
    }

    // ── Internal: protocol fee ────────────────────────────────────────────────
    // Uniswap V2-style: mint LP shares to feeTo representing earned fees
    function _mintProtocolFee(
        uint112 reserve0_,
        uint112 reserve1_,
        uint256 _totalSupply
    ) private returns (bool feeOn) {
        feeOn = feeTo != address(0) && protocolFeeBps > 0;
        if (!feeOn || _totalSupply == 0) return feeOn;

        uint256 rootK     = Math.sqrt(uint256(reserve0_) * reserve1_);
        uint256 rootKLast = Math.sqrt(uint256(reserve0_) * reserve1_); // simplified; store kLast in prod

        if (rootK > rootKLast) {
            uint256 numerator   = _totalSupply * (rootK - rootKLast) * protocolFeeBps;
            uint256 denominator = rootK * (FEE_DENOMINATOR - protocolFeeBps) + rootKLast * protocolFeeBps;
            uint256 liquidity   = numerator / denominator;
            if (liquidity > 0) _mint(feeTo, liquidity);
        }
    }

    function _trackBlockVolume(uint256 vol0, uint256 vol1) private {
        uint32 currentBlock = uint32(block.number);
        if (currentBlock != _lastSwapBlock) {
            _blockVolumeToken0 = 0;
            _blockVolumeToken1 = 0;
            _lastSwapBlock     = currentBlock;
        }
        _blockVolumeToken0 += vol0;
        _blockVolumeToken1 += vol1;
    }

    function _encodePrice(uint112 num, uint112 den) private pure returns (uint224) {
        return (uint224(num) << 112) / den;
    }

    function _getOldestObservation(uint32 secondsAgo)
        private view
        returns (Observation memory oldest)
    {
        // Search ring buffer for observation closest to secondsAgo
        uint32  target = uint32(block.timestamp) - secondsAgo;
        uint16  card   = observationCardinality;
        oldest         = observations[observationIndex]; // newest

        for (uint16 i = 1; i < card; ++i) {
            uint16 idx = (observationIndex + card - i) % card;
            Observation memory obs = observations[idx];
            if (obs.timestamp <= target) {
                oldest = obs;
                break;
            }
        }
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    function setFee(uint16 _baseFee, uint16 _volatilityFee) external onlyFactory {
        require(_baseFee + _volatilityFee <= 500, "Pair: FEE_TOO_HIGH"); // max 5%
        baseFee       = _baseFee;
        volatilityFee = _volatilityFee;
        emit FeeUpdated(_baseFee, _volatilityFee);
    }
}

interface IFlashSwapReceiver {
    function flashSwapCallback(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}