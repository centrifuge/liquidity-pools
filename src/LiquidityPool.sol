// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {IInvestmentManager} from "src/interfaces/IInvestmentManager.sol";
import "./interfaces/IERC7540.sol";
import "./interfaces/IERC7575.sol";
import "./interfaces/IERC20.sol";

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
    address public immutable share;

    /// @notice Escrow contract for tokens
    address public immutable escrow;

    /// @notice Liquidity Pool implementation contract
    IInvestmentManager public manager;

    /// @dev    Requests for Centrifuge pool are non-transferable and all have ID = 0
    uint256 constant REQUEST_ID = 0;

    // --- Events ---
    event File(bytes32 indexed what, address data);

    constructor(uint64 poolId_, bytes16 trancheId_, address asset_, address share_, address escrow_, address manager_) {
        poolId = poolId_;
        trancheId = trancheId_;
        asset = asset_;
        share = share_;
        escrow = escrow_;
        manager = IInvestmentManager(manager_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "manager") manager = IInvestmentManager(data);
        else revert("LiquidityPool/file-unrecognized-param");
        emit File(what, data);
    }

    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- ERC-7540 methods ---
    /// @inheritdoc IERC7540Deposit
    function requestDeposit(uint256 assets, address receiver, address owner, bytes memory data)
        public
        returns (uint256)
    {
        require(owner == msg.sender, "LiquidityPool/not-msg-sender");
        require(IERC20(asset).balanceOf(owner) >= assets, "LiquidityPool/insufficient-balance");

        require(manager.requestDeposit(address(this), assets, receiver, owner), "LiquidityPool/request-deposit-failed");
        SafeTransferLib.safeTransferFrom(asset, owner, address(escrow), assets);

        require(
            data.length == 0 || receiver.code.length == 0
                || IERC7540DepositReceiver(receiver).onERC7540DepositReceived(msg.sender, owner, REQUEST_ID, assets, data)
                    == IERC7540DepositReceiver.onERC7540DepositReceived.selector,
            "LiquidityPool/receiver-failed"
        );

        emit DepositRequest(receiver, owner, REQUEST_ID, msg.sender, assets);
        return REQUEST_ID;
    }

    /// @notice Uses EIP-2612 permit to set approval of asset, then transfers assets from msg.sender
    ///         into the Vault and submits a Request for asynchronous deposit/mint.
    function requestDepositWithPermit(
        uint256 assets,
        address receiver,
        bytes memory data,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        try IERC20Permit(asset).permit(msg.sender, address(this), assets, deadline, v, r, s) {} catch {}
        requestDeposit(assets, receiver, msg.sender, data);
    }

    /// @inheritdoc IERC7540Deposit
    function pendingDepositRequest(uint256, address owner) public view returns (uint256 pendingAssets) {
        pendingAssets = manager.pendingDepositRequest(address(this), owner);
    }

    /// @inheritdoc IERC7540Deposit
    function claimableDepositRequest(uint256, address owner) external view returns (uint256 claimableAssets) {
        claimableAssets = maxDeposit(owner);
    }

    /// @inheritdoc IERC7540Redeem
    function requestRedeem(uint256 shares, address receiver, address owner, bytes memory data)
        public
        returns (uint256)
    {
        require(IERC20Metadata(share).balanceOf(owner) >= shares, "LiquidityPool/insufficient-balance");
        require(manager.requestRedeem(address(this), shares, receiver, owner), "LiquidityPool/request-redeem-failed");
        require(_transferFrom(owner, address(escrow), shares), "LiquidityPool/transfer-failed");

        require(
            data.length == 0 || receiver.code.length == 0
                || IERC7540RedeemReceiver(receiver).onERC7540RedeemReceived(msg.sender, owner, REQUEST_ID, shares, data)
                    == IERC7540RedeemReceiver.onERC7540RedeemReceived.selector,
            "LiquidityPool/receiver-failed"
        );

        emit RedeemRequest(receiver, owner, REQUEST_ID, msg.sender, shares);
        return REQUEST_ID;
    }

    /// @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(uint256, address owner) public view returns (uint256 pendingShares) {
        pendingShares = manager.pendingRedeemRequest(address(this), owner);
    }

    /// @inheritdoc IERC7540Redeem
    function claimableRedeemRequest(uint256, address owner) external view returns (uint256 claimableShares) {
        claimableShares = maxRedeem(owner);
    }

    // --- Asynchronous cancellation methods ---
    /// @inheritdoc IERC7540CancelDeposit
    function cancelDepositRequest(uint256, address owner) external {
        require(owner == msg.sender, "LiquidityPool/not-the-owner");
        manager.cancelDepositRequest(address(this), owner);
        emit CancelDepositRequest(owner, REQUEST_ID, msg.sender);
    }

    /// @inheritdoc IERC7540CancelDeposit
    function pendingCancelDepositRequest(uint256, address owner) public view returns (bool isPending) {
        isPending = manager.pendingCancelDepositRequest(address(this), owner);
    }

    /// @inheritdoc IERC7540CancelDeposit
    function claimableCancelDepositRequest(uint256, address owner) public view returns (uint256 claimableAssets) {
        claimableAssets = manager.claimableCancelDepositRequest(address(this), owner);
    }

    /// @inheritdoc IERC7540CancelDeposit
    function claimCancelDepositRequest(uint256, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == owner, "LiquidityPool/not-the-owner");
        assets = manager.claimCancelDepositRequest(address(this), receiver, owner);
        emit ClaimCancelDepositRequest(msg.sender, receiver, owner, assets);
    }

    /// @inheritdoc IERC7540CancelRedeem
    function cancelRedeemRequest(uint256, address owner) external {
        require(msg.sender == owner, "LiquidityPool/not-the-owner");
        manager.cancelRedeemRequest(address(this), owner);
        emit CancelRedeemRequest(owner, REQUEST_ID, msg.sender);
    }

    /// @inheritdoc IERC7540CancelRedeem
    function pendingCancelRedeemRequest(uint256, address owner) public view returns (bool isPending) {
        isPending = manager.pendingCancelRedeemRequest(address(this), owner);
    }

    /// @inheritdoc IERC7540CancelRedeem
    function claimableCancelRedeemRequest(uint256, address owner) public view returns (uint256 claimableShares) {
        claimableShares = manager.claimableCancelRedeemRequest(address(this), owner);
    }

    /// @inheritdoc IERC7540CancelRedeem
    function claimCancelRedeemRequest(uint256, address receiver, address owner) external returns (uint256 shares) {
        require(msg.sender == owner, "LiquidityPool/not-the-owner");
        shares = manager.claimCancelRedeemRequest(address(this), receiver, owner);
        emit ClaimCancelRedeemRequest(msg.sender, receiver, owner, shares);
    }

    // --- ERC165 support ---
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC7540Deposit).interfaceId || interfaceId == type(IERC7540Redeem).interfaceId
            || interfaceId == type(IERC7575).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // --- ERC-4626 methods ---
    /// @inheritdoc IERC7575
    function totalAssets() external view returns (uint256) {
        return convertToAssets(IERC20Metadata(share).totalSupply());
    }

    /// @inheritdoc IERC7575
    /// @notice     The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///             The actual conversion MAY change between order submission and execution.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = manager.convertToShares(address(this), assets);
    }

    /// @inheritdoc IERC7575
    /// @notice     The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///             The actual conversion MAY change between order submission and execution.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = manager.convertToAssets(address(this), shares);
    }

    /// @inheritdoc IERC7575
    function maxDeposit(address owner) public view returns (uint256 maxAssets) {
        maxAssets = manager.maxDeposit(address(this), owner);
    }

    /// @inheritdoc IERC7575
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = manager.deposit(address(this), assets, receiver, msg.sender);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC7575
    function maxMint(address owner) public view returns (uint256 maxShares) {
        maxShares = manager.maxMint(address(this), owner);
    }

    /// @inheritdoc IERC7575
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = manager.mint(address(this), shares, receiver, msg.sender);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC7575
    function maxWithdraw(address owner) public view returns (uint256 maxAssets) {
        maxAssets = manager.maxWithdraw(address(this), owner);
    }

    /// @inheritdoc IERC7575
    /// @notice DOES NOT support owner != msg.sender since shares are already transferred on requestRedeem
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        require(msg.sender == owner, "LiquidityPool/not-the-owner");
        shares = manager.withdraw(address(this), assets, receiver, owner);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @inheritdoc IERC7575
    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        maxShares = manager.maxRedeem(address(this), owner);
    }

    /// @inheritdoc IERC7575
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

    // --- Helpers ---
    function exchangeRateLastUpdated() external view returns (uint64) {
        return manager.exchangeRateLastUpdated(address(this));
    }

    function _transferFrom(address from, address to, uint256 value) internal returns (bool) {
        (bool success, bytes memory data) = address(share).call(
            bytes.concat(
                abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value), bytes20(msg.sender)
            )
        );
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    function emitDepositClaimable(address owner, uint256 assets, uint256 shares) public auth {
        emit DepositClaimable(owner, REQUEST_ID, assets, shares);
    }

    function emitRedeemClaimable(address owner, uint256 assets, uint256 shares) public auth {
        emit RedeemClaimable(owner, REQUEST_ID, assets, shares);
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
