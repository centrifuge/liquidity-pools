// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";
import {MathLib} from "./util/MathLib.sol";
import {SafeTransferLib} from "./util/SafeTransferLib.sol";
import {IERC20, IERC20Metadata, IERC20Permit} from "./interfaces/IERC20.sol";
import {IERC7540} from "./interfaces/IERC7540.sol";

interface ManagerLike {
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
    function requestDeposit(address lp, uint256 assets, address sender, address operator) external returns (bool);
    function requestRedeem(address lp, uint256 shares, address operator) external returns (bool);
    function decreaseDepositRequest(address lp, uint256 assets, address operator) external;
    function decreaseRedeemRequest(address lp, uint256 shares, address operator) external;
    function cancelDepositRequest(address lp, address operator) external;
    function cancelRedeemRequest(address lp, address operator) external;
    function pendingDepositRequest(address lp, address operator) external view returns (uint256);
    function pendingRedeemRequest(address lp, address operator) external view returns (uint256);
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

    uint64 public immutable poolId;
    bytes16 public immutable trancheId;

    /// @notice The investment currency for this Liquidity Pool.
    ///         Each tranche of a Centrifuge pool can have multiple Liquidity Pools.
    ///         One Liquidity Pool for each supported asset.
    ///         Thus tranche shares can be linked to multiple LiquidityPools with different assets.
    /// @dev    Also known as the investment currency.
    address public immutable asset;

    /// @notice The restricted ERC-20 Liquidity Pool token. Has a ratio (token price) of underlying assets
    ///         exchanged on deposit/withdraw/redeem.
    /// @dev    Also known as tranche tokens.
    IERC20Metadata public immutable share;

    /// @notice Escrow contract for tokens
    address public immutable escrow;

    /// @notice Liquidity Pool business logic implementation contract
    ManagerLike public manager;

    // --- Events ---
    event File(bytes32 indexed what, address data);
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
    function file(bytes32 what, address data) public auth {
        if (what == "manager") manager = ManagerLike(data);
        else revert("LiquidityPool/file-unrecognized-param");
        emit File(what, data);
    }

    // --- ERC-4626 methods ---
    /// @return Total value of the shares, denominated in the asset of this Liquidity Pool
    function totalAssets() public view returns (uint256) {
        return convertToAssets(totalSupply());
    }

    /// @notice Calculates the amount of shares that any user would approximately get for the amount of assets provided.
    ///         The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///         The actual conversion will likely differ as the price changes between order submission and execution.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = manager.convertToShares(address(this), assets);
    }

    /// @notice Calculates the asset value for an amount of shares provided.
    ///         The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///         The actual conversion will likely differ as the price changes between order submission and execution.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = manager.convertToAssets(address(this), shares);
    }

    /// @return maxAssets that can be deposited into the Tranche by the receiver
    ///         after the epoch had been executed on Centrifuge.
    function maxDeposit(address receiver) public view returns (uint256 maxAssets) {
        maxAssets = manager.maxDeposit(address(this), receiver);
    }
    /// @notice Collect shares for deposited assets after Centrifuge epoch execution.
    ///         maxDeposit is the max amount of assets that can be deposited.

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = manager.deposit(address(this), assets, receiver, msg.sender);
        emit Deposit(address(this), receiver, assets, shares);
    }

    /// @notice Collect shares for deposited assets after Centrifuge epoch execution.
    ///         maxMint is the max amount of shares that can be minted.
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = manager.mint(address(this), shares, receiver, msg.sender);
        emit Deposit(address(this), receiver, assets, shares);
    }

    /// @notice maxShares that can be claimed by the receiver after the epoch has been executed on the Centrifuge side.
    function maxMint(address receiver) external view returns (uint256 maxShares) {
        maxShares = manager.maxMint(address(this), receiver);
    }

    /// @return maxAssets that the receiver can withdraw
    function maxWithdraw(address receiver) public view returns (uint256 maxAssets) {
        maxAssets = manager.maxWithdraw(address(this), receiver);
    }

    /// @notice Withdraw assets after successful epoch execution. Receiver will receive an exact amount of assets for
    ///         a certain amount of shares that has been redeemed from Owner during epoch execution.
    ///         DOES NOT support owner != msg.sender since shares are already transferred on requestRedeem
    /// @return shares that have been redeemed for the exact assets amount
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        require((msg.sender == owner), "LiquidityPool/not-the-owner");
        shares = manager.withdraw(address(this), assets, receiver, owner);
        emit Withdraw(address(this), receiver, owner, assets, shares);
    }

    /// @notice maxShares that can be redeemed by the owner after redemption was requested
    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        maxShares = manager.maxRedeem(address(this), owner);
    }

    /// @notice Redeem shares after successful epoch execution. Receiver will receive assets for
    /// @notice Redeem shares can only be called by the Owner or an authorized admin.
    ///         the exact amount of redeemed shares from Owner after epoch execution.
    ///         DOES NOT support owner != msg.sender since shares are already transferred on requestRedeem
    /// @return assets payout for the exact amount of redeemed shares
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        require((msg.sender == owner), "LiquidityPool/not-the-owner");
        assets = manager.redeem(address(this), shares, receiver, owner);
        emit Withdraw(address(this), receiver, owner, assets, shares);
    }

    // --- ERC-7540 methods ---
    /// @notice Request asset deposit for a receiver to be included in the next epoch execution.
    /// @notice Request can only be called by the owner of the assets
    ///         Asset is locked in the escrow on request submission
    function requestDeposit(uint256 assets, address operator) public {
        require(IERC20(asset).balanceOf(msg.sender) >= assets, "LiquidityPool/insufficient-balance");
        require(
            manager.requestDeposit(address(this), assets, msg.sender, operator), "LiquidityPool/request-deposit-failed"
        );
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(escrow), assets);
        emit DepositRequest(msg.sender, operator, assets);
    }

    /// @notice Similar to requestDeposit, but with a permit option
    function requestDepositWithPermit(uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        try IERC20Permit(asset).permit(msg.sender, address(this), assets, deadline, v, r, s) {} catch {}
        require(
            manager.requestDeposit(address(this), assets, msg.sender, msg.sender),
            "LiquidityPool/request-deposit-failed"
        );
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(escrow), assets);
        emit DepositRequest(msg.sender, msg.sender, assets);
    }

    /// @notice View the total amount the operator has requested to deposit but isn't able to deposit or mint yet
    /// @dev    Due to the asynchronous nature, this value might be outdated, and should only
    ///         be used for informational purposes.
    function pendingDepositRequest(address operator) external view returns (uint256 assets) {
        assets = manager.pendingDepositRequest(address(this), operator);
    }

    /// @notice Request share redemption for a receiver to be included in the next epoch execution.
    ///         DOES support flow where owner != msg.sender but has allowance to spend its shares
    ///         Shares are locked in the escrow on request submission
    function requestRedeem(uint256 shares, address operator, address owner) public {
        require(share.balanceOf(owner) >= shares, "LiquidityPool/insufficient-balance");
        require(manager.requestRedeem(address(this), shares, operator), "LiquidityPool/request-redeem-failed");

        // This is possible because of the trusted forwarder pattern -> msg.sender is forwarded
        // and the call can only be executed, if msg.sender has owner's approval to spend tokens
        require(transferFrom(owner, address(escrow), shares), "LiquidityPool/transfer-failed");

        emit RedeemRequest(msg.sender, operator, owner, shares);
    }

    /// @notice View the total amount the operator has requested to redeem but isn't able to withdraw or redeem yet
    /// @dev    Due to the asynchronous nature, this value might be outdated, and should only
    ///         be used for informational purposes.
    function pendingRedeemRequest(address operator) external view returns (uint256 shares) {
        shares = manager.pendingRedeemRequest(address(this), operator);
    }

    /// @dev Preview functions for async 4626 vaults revert
    function previewDeposit(uint256) external pure returns (uint256) {
        revert();
    }

    function previewMint(uint256) external pure returns (uint256) {
        revert();
    }

    function previewWithdraw(uint256) external pure returns (uint256) {
        revert();
    }

    function previewRedeem(uint256) external pure returns (uint256) {
        revert();
    }

    // --- Misc asynchronous vault methods ---
    /// @notice Request decreasing the outstanding deposit orders. Will return the assets once the order
    ///         on Centrifuge is successfully decreased.
    function decreaseDepositRequest(uint256 assets) public {
        manager.decreaseDepositRequest(address(this), assets, msg.sender);
        emit DecreaseDepositRequest(msg.sender, assets);
    }

    /// @notice Request cancelling the outstanding deposit orders. Will return the assets once the order
    ///         on Centrifuge is successfully cancelled.
    function cancelDepositRequest() public {
        manager.cancelDepositRequest(address(this), msg.sender);
        emit CancelDepositRequest(msg.sender);
    }

    /// @notice Request decreasing the outstanding redemption orders. Will return the shares once the order
    ///         on Centrifuge is successfully decreased.
    function decreaseRedeemRequest(uint256 shares) public {
        manager.decreaseRedeemRequest(address(this), shares, msg.sender);
        emit DecreaseRedeemRequest(msg.sender, shares);
    }

    /// @notice Request cancelling the outstanding redemption orders. Will return the shares once the order
    ///         on Centrifuge is successfully cancelled.
    function cancelRedeemRequest() public {
        manager.cancelRedeemRequest(address(this), msg.sender);
        emit CancelRedeemRequest(msg.sender);
    }

    function exchangeRateLastUpdated() public view returns (uint64) {
        return manager.exchangeRateLastUpdated(address(this));
    }

    // --- ERC-20 overrides ---
    function name() public view returns (string memory) {
        return share.name();
    }

    function symbol() public view returns (string memory) {
        return share.symbol();
    }

    function decimals() public view returns (uint8) {
        return share.decimals();
    }

    function totalSupply() public view returns (uint256) {
        return share.totalSupply();
    }

    function balanceOf(address owner) public view returns (uint256) {
        return share.balanceOf(owner);
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return share.allowance(owner, spender);
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        (bool success, bytes memory data) = address(share).call(
            bytes.concat(
                abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value), bytes20(msg.sender)
            )
        );
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    function transfer(address, uint256) external returns (bool) {
        (bool success, bytes memory data) = address(share).call(bytes.concat(msg.data, bytes20(msg.sender)));
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    function approve(address, uint256) external returns (bool) {
        (bool success, bytes memory data) = address(share).call(bytes.concat(msg.data, bytes20(msg.sender)));
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    // --- Helpers ---

    /// @dev In case of unsuccessful tx, parse the revert message
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
