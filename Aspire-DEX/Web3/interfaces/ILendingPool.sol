interface ILendingPool {
    event Deposit(address indexed asset, address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed asset, address indexed user, uint256 amount, uint256 shares);
    event Borrow(address indexed asset, address indexed user, uint256 amount, uint256 debtShares);
    event Repay(address indexed asset, address indexed user, uint256 amount, uint256 debtShares);

    function deposit(address asset, uint256 amount, address onBehalfOf) external returns (uint256 shares);
    function withdraw(address asset, uint256 shares, address to) external returns (uint256 amount);
    function borrow(address asset, uint256 amount, address onBehalfOf) external returns (uint256 debtShares);
    function repay(address asset, uint256 amount, address onBehalfOf) external returns (uint256 repaid);
    function accrueInterest(address asset) external;
}