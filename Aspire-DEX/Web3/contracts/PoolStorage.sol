// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title  PoolStorage
/// @notice Single source of truth for all lending state.
///         Intentionally NON-upgradeable — upgrading LendingPool cannot
///         accidentally corrupt position accounting.
///         Only authorised callers (LendingPool, LiquidationEngine) may mutate state.
contract PoolStorage is AccessControl {

    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant POOL_ROLE        = keccak256("POOL_ROLE");        // LendingPool
    bytes32 public constant LIQUIDATOR_ROLE  = keccak256("LIQUIDATOR_ROLE");  // LiquidationEngine
    bytes32 public constant GOVERNOR_ROLE    = keccak256("GOVERNOR_ROLE");

    // ── Constants ─────────────────────────────────────────────────────────────
    uint256 private constant RAY              = 1e27;   // index base unit
    uint256 private constant INITIAL_INDEX    = RAY;    // indexes start at 1.0 RAY

    // ── Core per-asset state ──────────────────────────────────────────────────
    /// @dev All index values are in RAY (1e27) precision.
    ///      Packed into 2 storage slots per asset:
    ///      slot 0: supplyIndex (uint128) | borrowIndex (uint128)
    ///      slot 1: totalSupplyShares (uint128) | totalDebtShares (uint128)
    ///              | lastAccrualTimestamp (uint40) | initialized (bool)
    struct AssetState {
        uint128 supplyIndex;           // grows with supply interest
        uint128 borrowIndex;           // grows with borrow interest
        uint128 totalSupplyShares;     // Σ supply shares outstanding
        uint128 totalDebtShares;       // Σ debt shares outstanding
        uint40  lastAccrualTimestamp;  // unix seconds of last accrual
        bool    initialized;
    }

    /// @dev Per-user, per-asset position.
    ///      Packed into 1 storage slot per (user, asset) pair.
    struct UserAssetPosition {
        uint128 supplyShares;  // user's share of the supply pool
        uint128 debtShares;    // user's share of the debt pool
    }

    // ── Storage ───────────────────────────────────────────────────────────────

    /// asset address → AssetState
    mapping(address => AssetState) private _assetStates;

    /// user address → asset address → UserAssetPosition
    mapping(address => mapping(address => UserAssetPosition)) private _positions;

    /// Enumerable list of all registered assets (for iteration in RiskEngine)
    address[] public registeredAssets;
    mapping(address => bool) public isRegistered;

    /// Enumerable list of all users who have ever had a position
    /// Used by off-chain workers; not security-critical
    address[] public knownUsers;
    mapping(address => bool) public isKnownUser;

    // ── Events ─────────────────────────────────────────────────────────────────
    event AssetRegistered(address indexed asset, uint256 timestamp);
    event SupplyAdded(address indexed user, address indexed asset, uint128 shares);
    event SupplyRemoved(address indexed user, address indexed asset, uint128 shares);
    event DebtAdded(address indexed user, address indexed asset, uint128 shares);
    event DebtRemoved(address indexed user, address indexed asset, uint128 shares);
    event DebtWrittenOff(address indexed user, address indexed asset, uint256 amount);
    event IndexUpdated(address indexed asset, uint128 supplyIndex, uint128 borrowIndex);

    // ── Errors ────────────────────────────────────────────────────────────────
    error AssetNotRegistered(address asset);
    error AssetAlreadyRegistered(address asset);
    error InsufficientShares(address user, address asset, uint128 have, uint128 need);
    error ZeroShares();
    error CallerNotAuthorized(address caller); 

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor(address governor) {
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(GOVERNOR_ROLE,      governor);
    }

    // ── Asset registration ────────────────────────────────────────────────────

    /// @notice Register a new borrowable/suppliable asset.
    ///         Must be called before LendingPool can use the asset.
    function registerAsset(address asset) external onlyRole(GOVERNOR_ROLE) {
        if (isRegistered[asset]) revert AssetAlreadyRegistered(asset);

        _assetStates[asset] = AssetState({
            supplyIndex:          uint128(INITIAL_INDEX),
            borrowIndex:          uint128(INITIAL_INDEX),
            totalSupplyShares:    0,
            totalDebtShares:      0,
            lastAccrualTimestamp: uint40(block.timestamp),
            initialized:          true
        });

        registeredAssets.push(asset);
        isRegistered[asset] = true;

        emit AssetRegistered(asset, block.timestamp);
    }

    // ── Index management (called by LendingPool.accrueInterest) ──────────────

    /// @notice Update stored indexes after interest accrual.
    ///         Caller (LendingPool) has already computed new index values.
    function setIndexes(
        address asset,
        uint128 newSupplyIndex,
        uint128 newBorrowIndex,
        uint40  newTimestamp
    ) external onlyRole(POOL_ROLE) {
        _requireRegistered(asset);
        AssetState storage state = _assetStates[asset];

        state.supplyIndex          = newSupplyIndex;
        state.borrowIndex          = newBorrowIndex;
        state.lastAccrualTimestamp = newTimestamp;

        emit IndexUpdated(asset, newSupplyIndex, newBorrowIndex);
    }

    // ── Supply (deposit) accounting ───────────────────────────────────────────

    function addUserSupply(address user, address asset, uint128 shares)
        external
        onlyRole(POOL_ROLE)
    {
        if (shares == 0) revert ZeroShares();
        _requireRegistered(asset);
        _trackUser(user);

        _positions[user][asset].supplyShares   += shares;
        _assetStates[asset].totalSupplyShares  += shares;

        emit SupplyAdded(user, asset, shares);
    }

    function removeUserSupply(address user, address asset, uint128 shares)
        external
    {
        // LendingPool (withdrawals) and LiquidationEngine (collateral seizure)
        // both need to remove supply
        if (!hasRole(POOL_ROLE, msg.sender) && !hasRole(LIQUIDATOR_ROLE, msg.sender))
            revert CallerNotAuthorized(msg.sender);

        if (shares == 0) revert ZeroShares();
        _requireRegistered(asset);

        uint128 current = _positions[user][asset].supplyShares;
        if (current < shares) revert InsufficientShares(user, asset, current, shares);

        unchecked {
            _positions[user][asset].supplyShares  -= shares;
            _assetStates[asset].totalSupplyShares -= shares;
        }

        emit SupplyRemoved(user, asset, shares);
    }

    // ── Debt accounting ───────────────────────────────────────────────────────

    function addUserDebt(address user, address asset, uint128 shares)
        external
        onlyRole(POOL_ROLE)
    {
        if (shares == 0) revert ZeroShares();
        _requireRegistered(asset);
        _trackUser(user);

        _positions[user][asset].debtShares   += shares;
        _assetStates[asset].totalDebtShares  += shares;

        emit DebtAdded(user, asset, shares);
    }

    function removeUserDebt(address user, address asset, uint128 shares)
        external
    {
        if (!hasRole(POOL_ROLE, msg.sender) && !hasRole(LIQUIDATOR_ROLE, msg.sender))
            revert CallerNotAuthorized(msg.sender);

        if (shares == 0) revert ZeroShares();
        _requireRegistered(asset);

        uint128 current = _positions[user][asset].debtShares;
        if (current < shares) revert InsufficientShares(user, asset, current, shares);

        unchecked {
            _positions[user][asset].debtShares  -= shares;
            _assetStates[asset].totalDebtShares -= shares;
        }

        emit DebtRemoved(user, asset, shares);
    }

    /// @notice Write off irrecoverable bad debt against the protocol.
    ///         Called by LiquidationEngine when a position is fully liquidated
    ///         but debt still remains with no collateral to cover it.
    ///         Debt shares are burned without a corresponding repayment —
    ///         the loss is socialised across all depositors via index dilution.
    function writeOffDebt(address user, address asset, uint256 /*amountHint*/)
        external
        onlyRole(LIQUIDATOR_ROLE)
    {
        _requireRegistered(asset);

        uint128 shares = _positions[user][asset].debtShares;
        if (shares == 0) return;

        unchecked {
            _positions[user][asset].debtShares  = 0;
            // Clamp to avoid underflow if rounding made totalDebt < shares
            uint128 total = _assetStates[asset].totalDebtShares;
            _assetStates[asset].totalDebtShares = total >= shares ? total - shares : 0;
        }

        emit DebtWrittenOff(user, asset, shares);
    }

    // ── Views (mutable state — storage pointer) ───────────────────────────────

    /// @notice Returns a storage reference — used internally by LendingPool
    ///         to read AND write state in a single SLOAD.
    ///         External callers should use getStateView().
    function getState(address asset)
        external
        onlyRole(POOL_ROLE)
        view
        returns (AssetState memory)
    {
        _requireRegistered(asset);
        return _assetStates[asset];
    }

    // ── Views (read-only) ─────────────────────────────────────────────────────

    /// @notice Returns a memory copy of asset state — safe for external callers.
    function getStateView(address asset)
        external
        view
        returns (AssetState memory)
    {
        _requireRegistered(asset);
        return _assetStates[asset];
    }

    function getUserSupplyShares(address user, address asset)
        external
        view
        returns (uint128)
    {
        return _positions[user][asset].supplyShares;
    }

    function getUserDebtShares(address user, address asset)
        external
        view
        returns (uint128)
    {
        return _positions[user][asset].debtShares;
    }

    function getUserPosition(address user, address asset)
        external
        view
        returns (uint128 supplyShares, uint128 debtShares)
    {
        UserAssetPosition storage pos = _positions[user][asset];
        return (pos.supplyShares, pos.debtShares);
    }

    /// @notice Compute the underlying token amount from shares + current index.
    function sharesToAmount(uint128 shares, uint128 index)
        external
        pure
        returns (uint256)
    {
        return (uint256(shares) * uint256(index)) / RAY;
    }

    /// @notice Compute shares from an underlying amount + current index.
    function amountToShares(uint256 amount, uint128 index)
        external
        pure
        returns (uint128)
    {
        if (index == 0) return 0;
        return uint128((amount * RAY) / uint256(index));
    }

    /// @notice Total supply in underlying token units (index-adjusted).
    function totalSupplyAmount(address asset) external view returns (uint256) {
        AssetState storage s = _assetStates[asset];
        return (uint256(s.totalSupplyShares) * uint256(s.supplyIndex)) / RAY;
    }

    /// @notice Total debt in underlying token units (index-adjusted).
    function totalDebtAmount(address asset) external view returns (uint256) {
        AssetState storage s = _assetStates[asset];
        return (uint256(s.totalDebtShares) * uint256(s.borrowIndex)) / RAY;
    }

    /// @notice Utilization rate in 1e18 precision (0 = 0%, 1e18 = 100%).
    function utilizationRate(address asset) external view returns (uint256) {
        AssetState storage s = _assetStates[asset];
        uint256 totalDebt    = (uint256(s.totalDebtShares) * uint256(s.borrowIndex)) / RAY;
        uint256 totalSupply  = (uint256(s.totalSupplyShares) * uint256(s.supplyIndex)) / RAY;
        if (totalSupply == 0) return 0;
        return (totalDebt * 1e18) / totalSupply;
    }

    function registeredAssetsLength() external view returns (uint256) {
        return registeredAssets.length;
    }

    function knownUsersLength() external view returns (uint256) {
        return knownUsers.length;
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _requireRegistered(address asset) internal view {
        if (!isRegistered[asset]) revert AssetNotRegistered(asset);
    }

    function _trackUser(address user) internal {
        if (!isKnownUser[user]) {
            isKnownUser[user] = true;
            knownUsers.push(user);
        }
    }

    // ── Role management ───────────────────────────────────────────────────────

    function grantPoolRole(address pool) external onlyRole(GOVERNOR_ROLE) {
        _grantRole(POOL_ROLE, pool);
    }

    function grantLiquidatorRole(address liquidator) external onlyRole(GOVERNOR_ROLE) {
        _grantRole(LIQUIDATOR_ROLE, liquidator);
    }
}