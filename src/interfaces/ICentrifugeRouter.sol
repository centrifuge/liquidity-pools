// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface ICentrifugeRouter {
    // --- Events ---
    event LockDepositRequest(
        address indexed vault, address indexed controller, address indexed owner, address sender, uint256 amount
    );
    event UnlockDepositRequest(address indexed vault, address indexed controller, address indexed receiver);
    event ExecuteLockedDepositRequest(address indexed vault, address indexed controller, address sender);

    /// @notice TODO
    function lockedRequests(address controller, address vault) external view returns (uint256 amount);

    /// @notice Determines whether requests for a given controller and vault can be claimed by anyone (permissionlessly)
    function opened(address controller, address vault) external view returns (bool);

    // --- Administration ---
    /// @notice TODO
    function recoverTokens(address token, address to, uint256 amount) external;

    // --- Deposit ---
    /// @notice TODO
    function requestDeposit(address vault, uint256 amount, address controller, address owner, uint256 topUp)
        external
        payable;

    /// @notice TODO
    function lockDepositRequest(address vault, uint256 amount, address controller, address owner) external payable;

    /// @notice Helper method to lock a deposit request, and enable permissionless claiming of that vault in 1 call
    function openLockDepositRequest(address vault, uint256 amount) external payable;

    /// @notice TODO
    function unlockDepositRequest(address vault, address receiver) external payable;

    /// @notice TODO
    function executeLockedDepositRequest(address vault, address controller) external payable;

    /// @notice TODO
    function claimDeposit(address vault, address receiver, address controller) external payable;

    /// @notice TODO
    function cancelDepositRequest(address vault, address controller) external;

    /// @notice TODO
    function claimCancelDepositRequest(address vault, address receiver, address controller) external;

    // --- Redeem ---
    /// @notice TODO
    function requestRedeem(address vault, uint256 amount, address controller, address owner) external payable;

    /// @notice TODO
    function claimRedeem(address vault, address receiver, address controller) external payable;

    // --- Manage permissionless claiming ---
    /// @notice Allow permissionless claiming
    function open(address vault) external;

    /// @notice Disallow permissionless claiming
    function close(address vault) external;

    /// @notice TODO
    function cancelRedeemRequest(address vault, address controller) external;

    /// @notice TODO
    function claimCancelRedeemRequest(address vault, address receiver, address controller) external;

    // --- Transfer ---
    /// @notice TODO
    function transfer(address asset, bytes32 recipient, uint128 amount) external;

    // --- ERC20 permit ---
    /// @notice TODO
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable;

    // --- ERC20 wrapping ---
    /// @notice TODO
    function wrap(address wrapper, uint256 amount, address receiver, address owner) external payable;

    /// @notice TODO
    function unwrap(address wrapper, uint256 amount, address receiver) external payable;

    // --- ERC20 auth transfer ---
    /// @notice TODO
    function authTransferFrom(address vault, address sender, address owner, address recipient, uint256 amount)
        external;

    // --- Batching ---
    /// @notice TODO
    function multicall(bytes[] memory data) external payable;

    // --- View Methods ---
    /// @notice TODO
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address);

    /// @notice TODO
    function estimate(bytes calldata payload) external view returns (uint256 amount);
}
