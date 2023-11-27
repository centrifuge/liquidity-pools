// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";
import {MathLib} from "./util/MathLib.sol";
import {SafeTransferLib} from "./util/SafeTransferLib.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {IERC20, IERC20Metadata, IERC20Permit} from "./interfaces/IERC20.sol";
import {IERC7540, IERC165, IERC7540Deposit, IERC7540Redeem} from "./interfaces/IERC7540.sol";

interface ManagerLike {
    function requestDeposit(address lp, uint256 assets, address receiver, address owner) external returns (bool);
    function requestRedeem(address lp, uint256 shares, address receiver, address owner) external returns (bool);
    function decreaseDepositRequest(address lp, uint256 assets, address owner) external;
    function decreaseRedeemRequest(address lp, uint256 shares, address owner) external;
    function cancelDepositRequest(address lp, address owner) external;
    function cancelRedeemRequest(address lp, address owner) external;
    function pendingDepositRequest(address lp, address owner) external view returns (uint256);
    function pendingRedeemRequest(address lp, address owner) external view returns (uint256);
    function deposit(address lp, uint256 assets, address receiver, address owner) external returns (uint256);
    function mint(address lp, uint256 shares, address receiver, address owner) external returns (uint256);
    function withdraw(address lp, uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(address lp, uint256 shares, address receiver, address owner) external returns (uint256);
    function maxDeposit(address lp, address receiver) external view returns (uint256);
    function maxMint(address lp, address receiver) external view returns (uint256);
    function maxWithdraw(address lp, address receiver) external view returns (uint256);
    function maxRedeem(address lp, address receiver) external view returns (uint256);
    function convertToShares(address lp, uint256 assets) external view returns (uint256);
    function convertToAssets(address lp, uint256 shares) external view returns (uint256);
    function exchangeRateLastUpdated(address liquidityPool) external view returns (uint64 lastUpdated);
}

/// @title  Liquidity Pool
/// @notice Liquidity Pool implementation for Centrifuge pools
///         following the ERC-7540 Asynchronous Tokenized Vault standard
///
/// @dev    Each Liquidity Pool is a tokenized vault issuing shares of Centrifuge tranches as restricted ERC-20 tokens
///         against currency deposits based on the current share price.
///
///         ERC-7540 is an extension of the ERC-4626 standard by 'requestDeposit' & 'requestRedeem' methods, where
///         deposit and redeem orders are submitted to the pools to be included in the execution of the following epoch.
///         After execution users can use the deposit, mint, redeem and withdraw functions to get their shares
///         and/or assets from the pools.
contract LiquidityPool is Auth, IERC7540 {
    using MathLib for uint256;

    /// @notice Identifier of the Centrifuge pool
    uint64 public immutable poolId;

    /// @notice Identifier of the tranche of the Centrifuge pool
    bytes16 public immutable trancheId;

    /// @notice The investment currency (asset) for this Liquidity Pool.
    ///         Each tranche of a Centrifuge pool can have multiple Liquidity Pools.
    ///         One Liquidity Pool for each supported investment currency.
    ///         Thus tranche shares can be linked to multiple Liquidity Pools with different currencies.
    address public immutable asset;

    /// @notice The restricted ERC-20 Liquidity Pool share (tranche token).
    ///         Has a ratio (token price) of underlying assets exchanged on deposit/mint/withdraw/redeem.
    IERC20Metadata public immutable share;

    /// @notice Liquidity Pool implementation contract
    ManagerLike public manager;

    /// @notice Escrow contract for tokens
    address public immutable escrow;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event DepositClaimable(address indexed owner, uint256 assets, uint256 shares);
    event RedeemClaimable(address indexed owner, uint256 assets, uint256 shares);
    event DecreaseDepositRequest(address indexed sender, uint256 assets);
    event DecreaseRedeemRequest(address indexed sender, uint256 shares);
    event CancelDepositRequest(address indexed sender);
    event CancelRedeemRequest(address indexed sender);

    constructor(uint64 poolId_, bytes16 trancheId_, address asset_, address share_, address escrow_, address manager_) {
        poolId = poolId_;
        trancheId = trancheId_;
        asset = asset_;
        share = IERC20Metadata(share_);
        escrow = escrow_;
        manager = ManagerLike(manager_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "manager") manager = ManagerLike(data);
        else revert("LiquidityPool/file-unrecognized-param");
        emit File(what, data);
    }

    // --- ERC-7540 methods ---
    /// @inheritdoc IERC7540Deposit
    function requestDeposit(uint256 assets, address receiver) public {
        require(IERC20(asset).balanceOf(msg.sender) >= assets, "LiquidityPool/insufficient-balance");
        require(
            manager.requestDeposit(address(this), assets, receiver, msg.sender), "LiquidityPool/request-deposit-failed"
        );
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(escrow), assets);
        emit DepositRequest(msg.sender, receiver, msg.sender, assets);
    }

    /// @notice Uses EIP-2612 permit to set approval of asset, then transfers assets from msg.sender
    ///         into the Vault and submits a Request for asynchronous deposit/mint.
    function requestDepositWithPermit(uint256 assets, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        try IERC20Permit(asset).permit(msg.sender, address(this), assets, deadline, v, r, s) {} catch {}
        requestDeposit(assets, receiver);
    }

    /// @inheritdoc IERC7540Deposit
    function pendingDepositRequest(address owner) external view returns (uint256 assets) {
        assets = manager.pendingDepositRequest(address(this), owner);
    }

    /// @inheritdoc IERC7540Redeem
    function requestRedeem(uint256 shares, address receiver, address owner) external {
        require(share.balanceOf(owner) >= shares, "LiquidityPool/insufficient-balance");
        require(manager.requestRedeem(address(this), shares, receiver, owner), "LiquidityPool/request-redeem-failed");
        require(transferFrom(owner, address(escrow), shares), "LiquidityPool/transfer-failed");
        emit RedeemRequest(msg.sender, receiver, owner, shares);
    }

    /// @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(address owner) external view returns (uint256 shares) {
        shares = manager.pendingRedeemRequest(address(this), owner);
    }

    // --- Misc asynchronous vault methods ---
    /// @notice Request decreasing the outstanding deposit orders.
    function decreaseDepositRequest(uint256 assets) external {
        manager.decreaseDepositRequest(address(this), assets, msg.sender);
        emit DecreaseDepositRequest(msg.sender, assets);
    }

    /// @notice Request cancelling the outstanding deposit orders.
    function cancelDepositRequest() external {
        manager.cancelDepositRequest(address(this), msg.sender);
        emit CancelDepositRequest(msg.sender);
    }

    /// @notice Request decreasing the outstanding redemption orders.
    function decreaseRedeemRequest(uint256 shares) external {
        manager.decreaseRedeemRequest(address(this), shares, msg.sender);
        emit DecreaseRedeemRequest(msg.sender, shares);
    }

    /// @notice Request cancelling the outstanding redemption orders.
    function cancelRedeemRequest() external {
        manager.cancelRedeemRequest(address(this), msg.sender);
        emit CancelRedeemRequest(msg.sender);
    }

    function exchangeRateLastUpdated() external view returns (uint64) {
        return manager.exchangeRateLastUpdated(address(this));
    }

    // --- ERC165 support ---
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC7540Deposit).interfaceId
            || interfaceId == type(IERC7540Redeem).interfaceId;
    }

    // --- ERC-4626 methods ---
    /// @inheritdoc IERC4626
    function totalAssets() external view returns (uint256) {
        return convertToAssets(totalSupply());
    }

    /// @inheritdoc IERC4626
    /// @notice     The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///             The actual conversion MAY change between order submission and execution.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = manager.convertToShares(address(this), assets);
    }

    /// @inheritdoc IERC4626
    /// @notice     The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///             The actual conversion MAY change between order submission and execution.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = manager.convertToAssets(address(this), shares);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address owner) external view returns (uint256 maxAssets) {
        maxAssets = manager.maxDeposit(address(this), owner);
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = manager.deposit(address(this), assets, receiver, msg.sender);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function maxMint(address owner) external view returns (uint256 maxShares) {
        maxShares = manager.maxMint(address(this), owner);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = manager.mint(address(this), shares, receiver, msg.sender);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner) external view returns (uint256 maxAssets) {
        maxAssets = manager.maxWithdraw(address(this), owner);
    }

    /// @inheritdoc IERC4626
    /// @notice DOES NOT support owner != msg.sender since shares are already transferred on requestRedeem
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        require(msg.sender == owner, "LiquidityPool/not-the-owner");
        shares = manager.withdraw(address(this), assets, receiver, owner);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        maxShares = manager.maxRedeem(address(this), owner);
    }

    /// @inheritdoc IERC4626
    /// @notice     DOES NOT support owner != msg.sender since shares are already transferred on requestRedeem
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == owner, "LiquidityPool/not-the-owner");
        assets = manager.redeem(address(this), shares, receiver, owner);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @dev Preview functions for ERC-7540 vaults revert
    function previewDeposit(uint256) external pure returns (uint256) {
        revert();
    }

    /// @dev Preview functions for ERC-7540 vaults revert
    function previewMint(uint256) external pure returns (uint256) {
        revert();
    }

    /// @dev Preview functions for ERC-7540 vaults revert
    function previewWithdraw(uint256) external pure returns (uint256) {
        revert();
    }

    /// @dev Preview functions for ERC-7540 vaults revert
    function previewRedeem(uint256) external pure returns (uint256) {
        revert();
    }

    // --- ERC-20 overrides ---
    /// @inheritdoc IERC20Metadata
    function name() external view returns (string memory) {
        return share.name();
    }

    /// @inheritdoc IERC20Metadata
    function symbol() external view returns (string memory) {
        return share.symbol();
    }

    /// @inheritdoc IERC20Metadata
    function decimals() external view returns (uint8) {
        return share.decimals();
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256) {
        return share.totalSupply();
    }

    /// @inheritdoc IERC20
    function balanceOf(address owner) external view returns (uint256) {
        return share.balanceOf(owner);
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view returns (uint256) {
        return share.allowance(owner, spender);
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        (bool success, bytes memory data) = address(share).call(
            bytes.concat(
                abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value), bytes20(msg.sender)
            )
        );
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    /// @inheritdoc IERC20
    function transfer(address, uint256) external returns (bool) {
        (bool success, bytes memory data) = address(share).call(bytes.concat(msg.data, bytes20(msg.sender)));
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    /// @inheritdoc IERC20
    function approve(address, uint256) external returns (bool) {
        (bool success, bytes memory data) = address(share).call(bytes.concat(msg.data, bytes20(msg.sender)));
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    // --- Helpers ---
    function emitDepositClaimable(address owner, uint256 assets, uint256 shares) public auth {
        emit DepositClaimable(owner, assets, shares);
    }

    function emitRedeemClaimable(address owner, uint256 assets, uint256 shares) public auth {
        emit RedeemClaimable(owner, assets, shares);
    }

    function _successCheck(bool success) internal pure {
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }
}
