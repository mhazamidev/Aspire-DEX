// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IInterestRateModel.sol";
import "../interfaces/IRiskEngine.sol";
import "./PoolStorage.sol";

contract LendingPool is
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant RISK_ADMIN_ROLE = keccak256("RISK_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 private constant RAY = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    PoolStorage public poolStorage;
    IInterestRateModel public interestRateModel;
    IRiskEngine public riskEngine;
    address public treasury;
    uint256 public reserveFactor; // portion of interest going to treasury (1e18 = 100%)

    event Deposit(
        address indexed asset,
        address indexed user,
        uint256 amount,
        uint256 shares
    );
    event Withdraw(
        address indexed asset,
        address indexed user,
        uint256 amount,
        uint256 shares
    );
    event Borrow(
        address indexed asset,
        address indexed user,
        uint256 amount,
        uint256 debtShares
    );
    event Repay(
        address indexed asset,
        address indexed user,
        uint256 amount,
        uint256 debtShares
    );
    event InterestAccrued(
        address indexed asset,
        uint256 borrowIndex,
        uint256 timestamp
    );
    event ReserveFactorUpdated(uint256 oldFactor, uint256 newFactor);

    error AssetNotActive(address asset);
    error AssetNotBorrowable(address asset);
    error InsufficientCollateral(address user, uint256 healthFactor);
    error InsufficientLiquidity(
        address asset,
        uint256 requested,
        uint256 available
    );
    error InvalidAmount();
    error HealthFactorTooLow(address user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _poolStorage,
        address _interestRateModel,
        address _riskEngine,
        address _treasury,
        uint256 _reserveFactor,
        address _governor
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        poolStorage = PoolStorage(_poolStorage);
        interestRateModel = IInterestRateModel(_interestRateModel);
        riskEngine = IRiskEngine(_riskEngine);
        treasury = _treasury;
        reserveFactor = _reserveFactor;

        _grantRole(DEFAULT_ADMIN_ROLE, _governor);
        _grantRole(GOVERNOR_ROLE, _governor);
    }

    // ── Deposit ───────────────────────────────────────────────────────────────
    // deposit — uses poolStorage.amountToShares()
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();
        _requireActiveAsset(asset);
        accrueInterest(asset);

        PoolStorage.AssetState memory state = poolStorage.getStateView(asset);
        shares = poolStorage.amountToShares(amount, state.supplyIndex);

        poolStorage.addUserSupply(onBehalfOf, asset, uint128(shares));
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(asset, onBehalfOf, amount, shares);
    }

    // ── Withdraw ──────────────────────────────────────────────────────────────

    function withdraw(
        address asset,
        uint256 shares,
        address to
    ) external nonReentrant whenNotPaused returns (uint256 amount) {
        if (shares == 0) revert InvalidAmount();

        accrueInterest(asset);

        PoolStorage.AssetState memory state = poolStorage.getState(asset);
        amount = _fromShares(shares, state.supplyIndex);

        uint256 available = IERC20(asset).balanceOf(address(this));
        if (amount > available)
            revert InsufficientLiquidity(asset, amount, available);

        poolStorage.removeUserSupply(msg.sender, asset, uint128(shares));
        state.totalSupplyShares -= uint128(shares);

        IERC20(asset).safeTransfer(to, amount);

        // Verify health factor after withdrawal
        if (poolStorage.getUserDebtShares(msg.sender, asset) > 0) {
            uint256 hf = riskEngine.getHealthFactor(msg.sender);
            if (hf < 1e18) revert HealthFactorTooLow(msg.sender);
        }

        emit Withdraw(asset, msg.sender, amount, shares);
    }

    // ── Borrow ────────────────────────────────────────────────────────────────

    // borrow — health factor checked AFTER state is written, then reverted if bad
    function borrow(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external nonReentrant whenNotPaused returns (uint256 debtShares) {
        if (amount == 0) revert InvalidAmount();
        _requireActiveAsset(asset);
        _requireBorrowableAsset(asset);
        accrueInterest(asset);

        uint256 available = IERC20(asset).balanceOf(address(this));
        if (amount > available)
            revert InsufficientLiquidity(asset, amount, available);

        PoolStorage.AssetState memory state = poolStorage.getStateView(asset);
        debtShares = poolStorage.amountToShares(amount, state.borrowIndex);

        poolStorage.addUserDebt(onBehalfOf, asset, uint128(debtShares));

        // CRITICAL: health factor check AFTER writing debt
        // If HF is now below 1.0, revert the entire transaction (including the addUserDebt)
        uint256 hf = riskEngine.getHealthFactor(onBehalfOf);
        if (hf < 1e18) revert InsufficientCollateral(onBehalfOf, hf);

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Borrow(asset, onBehalfOf, amount, debtShares);
    }

    // ── Repay ─────────────────────────────────────────────────────────────────

    function repay(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external nonReentrant whenNotPaused returns (uint256 repaid) {
        if (amount == 0) revert InvalidAmount();

        accrueInterest(asset);

        PoolStorage.AssetState memory state = poolStorage.getState(asset);
        uint256 userDebtShares = poolStorage.getUserDebtShares(
            onBehalfOf,
            asset
        );
        uint256 userDebtAmount = _fromShares(userDebtShares, state.borrowIndex);

        // Cap repayment at actual debt
        repaid = amount > userDebtAmount ? userDebtAmount : amount;
        uint256 sharesToBurn = _toShares(repaid, state.borrowIndex);

        state.totalDebtShares -= uint128(sharesToBurn);
        poolStorage.removeUserDebt(onBehalfOf, asset, uint128(sharesToBurn));

        IERC20(asset).safeTransferFrom(msg.sender, address(this), repaid);

        emit Repay(asset, onBehalfOf, repaid, sharesToBurn);
    }

    // ── Interest Accrual ──────────────────────────────────────────────────────

    function accrueInterest(address asset) public {
        PoolStorage.AssetState memory state = poolStorage.getStateView(asset);
        uint256 elapsed = block.timestamp - state.lastAccrualTimestamp;
        if (elapsed == 0) return;

        uint256 totalDebt = poolStorage.totalDebtAmount(asset);
        uint256 totalLiquidity = IERC20(asset).balanceOf(address(this)) +
            totalDebt;

        uint256 borrowRate = interestRateModel.getBorrowRate(
            totalDebt,
            totalLiquidity
        );
        uint256 interestFactor = RAY +
            (borrowRate * elapsed * RAY) /
            (SECONDS_PER_YEAR * 1e18);

        uint128 newBorrowIndex = uint128(
            (uint256(state.borrowIndex) * interestFactor) / RAY
        );

        // Mint reserve shares to treasury
        uint256 interestEarned = (totalDebt *
            (newBorrowIndex - state.borrowIndex)) / state.borrowIndex;
        uint256 reserveAmount = (interestEarned * reserveFactor) / 1e18;
        if (reserveAmount > 0) {
            uint128 reserveShares = poolStorage.amountToShares(
                reserveAmount,
                state.supplyIndex
            );
            poolStorage.addUserSupply(treasury, asset, reserveShares);
        }

        // Supply index grows proportional to interest net of reserve
        uint256 supplyRate = interestRateModel.getSupplyRate(
            totalDebt,
            totalLiquidity,
            reserveFactor
        );
        uint256 supplyFactor = RAY +
            (supplyRate * elapsed * RAY) /
            (SECONDS_PER_YEAR * 1e18);
        uint128 newSupplyIndex = uint128(
            (uint256(state.supplyIndex) * supplyFactor) / RAY
        );

        poolStorage.setIndexes(
            asset,
            newSupplyIndex,
            newBorrowIndex,
            uint40(block.timestamp)
        );

        emit InterestAccrued(asset, newBorrowIndex, block.timestamp);
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    function _toShares(
        uint256 amount,
        uint256 index
    ) internal pure returns (uint256) {
        return (amount * RAY) / index;
    }

    function _fromShares(
        uint256 shares,
        uint256 index
    ) internal pure returns (uint256) {
        return (shares * index) / RAY;
    }

    function _requireActiveAsset(address asset) internal view {
        IRiskEngine.AssetConfig memory cfg = riskEngine.getAssetConfig(asset);
        if (!cfg.isActive) revert AssetNotActive(asset);
    }

    function _requireBorrowableAsset(address asset) internal view {
        IRiskEngine.AssetConfig memory cfg = riskEngine.getAssetConfig(asset);
        if (!cfg.isBorrowable) revert AssetNotBorrowable(asset);
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyRole(GOVERNOR_ROLE) {}

    // ── Admin ─────────────────────────────────────────────────────────────────

    function setReserveFactor(
        uint256 newFactor
    ) external onlyRole(RISK_ADMIN_ROLE) {
        require(newFactor <= 1e18, "LendingPool: RESERVE_TOO_HIGH");
        emit ReserveFactorUpdated(reserveFactor, newFactor);
        reserveFactor = newFactor;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
