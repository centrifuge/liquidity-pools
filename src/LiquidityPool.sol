// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";
import {MathLib} from "./util/MathLib.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";

interface ERC20PermitLike {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface TrancheTokenLike is IERC20, ERC20PermitLike {
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
}

interface InvestmentManagerLike {
    function processDeposit(address liquidityPool, uint256 assets, address receiver, address owner)
        external
        returns (uint256);
    function processMint(address liquidityPool, uint256 shares, address receiver, address owner)
        external
        returns (uint256);
    function processWithdraw(address liquidityPool, uint256 assets, address receiver, address owner)
        external
        returns (uint256);
    function processRedeem(address liquidityPool, uint256 shares, address receiver, address owner)
        external
        returns (uint256);
    function maxDeposit(address liquidityPool, address user) external view returns (uint256);
    function maxMint(address liquidityPool, address user) external view returns (uint256);
    function maxWithdraw(address liquidityPool, address user) external view returns (uint256);
    function maxRedeem(address liquidityPool, address user) external view returns (uint256);
    function totalAssets(address liquidityPool, uint256 totalSupply) external view returns (uint256);
    function convertToShares(address liquidityPool, uint256 assets) external view returns (uint256);
    function convertToAssets(address liquidityPool, uint256 shares) external view returns (uint256);
    function previewDeposit(address liquidityPool, address user, uint256 assets) external view returns (uint256);
    function previewMint(address liquidityPool, address user, uint256 shares) external view returns (uint256);
    function previewWithdraw(address liquidityPool, address user, uint256 assets) external view returns (uint256);
    function previewRedeem(address liquidityPool, address user, uint256 shares) external view returns (uint256);
    function requestRedeem(address liquidityPool, uint256 shares, address receiver) external;
    function requestDeposit(address liquidityPool, uint256 assets, address receiver) external;
    function decreaseDepositRequest(address liquidityPool, uint256 assets, address receiver) external;
    function decreaseRedeemRequest(address liquidityPool, uint256 shares, address receiver) external;
    function cancelDepositRequest(address liquidityPool, address receiver) external;
    function cancelRedeemRequest(address liquidityPool, address receiver) external;
    function userDepositRequest(address liquidityPool, address user) external view returns (uint256);
    function userRedeemRequest(address liquidityPool, address user) external view returns (uint256);
}

/// @title  Liquidity Pool
/// @notice Liquidity Pool implementation for Centrifuge pools
///         following the EIP4626 standard, with asynchronous extension methods.
///
/// @dev    Each Liquidity Pool is a tokenized vault issuing shares of Centrifuge tranches as restricted ERC20 tokens
///         against currency deposits based on the current share price.
///
///         This is extending the EIP4626 standard by 'requestDeposit' & 'requestRedeem' functions, where deposit and
///         redeem orders are submitted to the pools to be included in the execution of the following epoch. After
///         execution users can use the deposit, mint, redeem and withdraw functions to get their shares
///         and/or assets from the pools.
contract LiquidityPool is Auth, IERC4626 {
    using MathLib for uint256;

    uint64 public immutable poolId;
    bytes16 public immutable trancheId;

    /// @notice The investment currency for this Liquidity Pool.
    ///         Each tranche of a Centrifuge pool can have multiple Liquidity Pools. A Liquidity Pool for each supported asset.
    ///         Thus tranche shares can be linked to multiple LiquidityPools with different assets.
    /// @dev    Also known as the investment currency.
    address public immutable asset;

    /// @notice The restricted ERC-20 Liquidity Pool token. Has a ratio (token price) of underlying assets
    ///         exchanged on deposit/withdraw/redeem.
    /// @dev    Also known as tranche tokens.
    TrancheTokenLike public immutable share;

    InvestmentManagerLike public investmentManager;

    /// @notice Tranche token price, denominated in the asset
    uint128 public latestPrice;

    /// @notice Timestamp of the last price update
    uint256 public lastPriceUpdate;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event DepositRequest(address indexed owner, uint256 assets);
    event RedeemRequest(address indexed owner, uint256 shares);
    event DecreaseDepositRequest(address indexed owner, uint256 assets);
    event DecreaseRedeemRequest(address indexed owner, uint256 shares);
    event CancelDepositRequest(address indexed owner);
    event CancelRedeemRequest(address indexed owner);
    event PriceUpdate(uint128 price);

    constructor(uint64 poolId_, bytes16 trancheId_, address asset_, address share_, address investmentManager_) {
        poolId = poolId_;
        trancheId = trancheId_;
        asset = asset_;
        share = TrancheTokenLike(share_);
        investmentManager = InvestmentManagerLike(investmentManager_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev Owner needs to be the msg.sender
    modifier withApproval(address owner) {
        require((msg.sender == owner), "LiquidityPool/no-approval");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) public auth {
        if (what == "investmentManager") investmentManager = InvestmentManagerLike(data);
        else revert("LiquidityPool/file-unrecognized-param");
        emit File(what, data);
    }

    // --- ERC4626 functions ---
    /// @return Total value of the shares, denominated in the asset of this Liquidity Pools
    function totalAssets() public view returns (uint256) {
        return investmentManager.totalAssets(address(this), totalSupply());
    }

    /// @notice Calculates the amount of shares that any user would approximately get for the amount of assets provided.
    ///         The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///         The actual conversion will likely differ as the price changes between order submission and execution.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = investmentManager.convertToShares(address(this), assets);
    }

    /// @notice Calculates the asset value for an amount of shares provided.
    ///         The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///         The actual conversion will likely differ as the price changes between order submission and execution.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = investmentManager.convertToAssets(address(this), shares);
    }

    /// @return maxAssets that can be deposited into the Tranche by the receiver after the epoch had been executed on Centrifuge.
    function maxDeposit(address receiver) public view returns (uint256 maxAssets) {
        maxAssets = investmentManager.maxDeposit(address(this), receiver);
    }

    /// @return shares that any user would get for an amount of assets provided
    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        shares = investmentManager.previewDeposit(address(this), msg.sender, assets);
    }

    /// @notice Collect shares for deposited assets after Centrifuge epoch execution.
    ///         maxDeposit is the max amount of shares that can be collected.
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = investmentManager.processDeposit(address(this), assets, receiver, msg.sender);
        emit Deposit(address(this), receiver, assets, shares);
    }

    /// @notice Collect shares for deposited assets after Centrifuge epoch execution.
    ///         maxMint is the max amount of shares that can be collected.
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = investmentManager.processMint(address(this), shares, receiver, msg.sender);
        emit Deposit(address(this), receiver, assets, shares);
    }

    /// @notice maxShares that can be claimed by the receiver after the epoch has been executed on the Centrifuge side.
    function maxMint(address receiver) external view returns (uint256 maxShares) {
        maxShares = investmentManager.maxMint(address(this), receiver);
    }

    /// @return assets that any user would get for an amount of shares provided -> convertToAssets
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        assets = investmentManager.previewMint(address(this), msg.sender, shares);
    }

    /// @return maxAssets that the receiver can withdraw
    function maxWithdraw(address receiver) public view returns (uint256 maxAssets) {
        maxAssets = investmentManager.maxWithdraw(address(this), receiver);
    }

    /// @return shares that a user would need to redeem in order to receive the given amount of assets -> convertToAssets
    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        shares = investmentManager.previewWithdraw(address(this), msg.sender, assets);
    }

    /// @notice Withdraw assets after successful epoch execution. Receiver will receive an exact amount of assets for
    ///         a certain amount of shares that has been redeemed from Owner during epoch execution.
    /// @return shares that have been redeemed for the exact assets amount
    function withdraw(uint256 assets, address receiver, address owner)
        public
        withApproval(owner)
        returns (uint256 shares)
    {
        shares = investmentManager.processWithdraw(address(this), assets, receiver, owner);
        emit Withdraw(address(this), receiver, owner, assets, shares);
    }

    /// @notice maxShares that can be redeemed by the owner after redemption was requested
    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        maxShares = investmentManager.maxRedeem(address(this), owner);
    }

    /// @return assets that any user could redeem for a given amount of shares
    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        assets = investmentManager.previewRedeem(address(this), msg.sender, shares);
    }

    /// @notice Redeem shares after successful epoch execution. Receiver will receive assets for
    /// @notice Redeem shares can only be called by the Owner or an authorized admin.
    ///         the exact amount of redeemed shares from Owner after epoch execution.
    /// @return assets payout for the exact amount of redeemed shares
    function redeem(uint256 shares, address receiver, address owner)
        public
        withApproval(owner)
        returns (uint256 assets)
    {
        assets = investmentManager.processRedeem(address(this), shares, receiver, owner);
        emit Withdraw(address(this), receiver, owner, assets, shares);
    }

    // --- Asynchronous 4626 functions ---
    /// @notice Request asset deposit for a receiver to be included in the next epoch execution.
    /// @notice Request can only be called by the owner of the assets
    ///         Asset is locked in the escrow on request submission
    function requestDeposit(uint256 assets, address owner) public withApproval(owner) {
        investmentManager.requestDeposit(address(this), assets, owner);
        emit DepositRequest(owner, assets);
    }

    /// @notice Similar to requestDeposit, but with a permit option.
    function requestDepositWithPermit(uint256 assets, address owner, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        _withPermit(asset, owner, address(investmentManager), assets, deadline, v, r, s);
        investmentManager.requestDeposit(address(this), assets, owner);
        emit DepositRequest(owner, assets);
    }

    /// @notice View the total amount the user has requested to deposit but isn't able to deposit or mint yet
    function userDepositRequest(address owner) external view returns (uint256 assets) {
        assets = investmentManager.userDepositRequest(address(this), owner);
    }

    /// @notice Request decreasing the outstanding deposit orders. Will return the assets once the order
    ///         on Centrifuge is successfully decreased.
    function decreaseDepositRequest(uint256 assets, address owner) public withApproval(owner) {
        investmentManager.decreaseDepositRequest(address(this), assets, owner);
        emit DecreaseDepositRequest(owner, assets);
    }

    /// @notice Request cancelling the outstanding deposit orders. Will return the assets once the order
    ///         on Centrifuge is successfully cancelled.
    function cancelDepositRequest(address owner) public withApproval(owner) {
        investmentManager.cancelDepositRequest(address(this), owner);
        emit CancelDepositRequest(owner);
    }

    /// @notice Request share redemption for a receiver to be included in the next epoch execution.
    /// @notice Request can only be called by the owner of the shares
    ///         Shares are locked in the escrow on request submission
    function requestRedeem(uint256 shares, address owner) public withApproval(owner) {
        investmentManager.requestRedeem(address(this), shares, owner);
        emit RedeemRequest(owner, shares);
    }

    /// @notice Similar to requestRedeem, but with a permit option.
    function requestRedeemWithPermit(uint256 shares, address owner, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        _withPermit(address(share), owner, address(investmentManager), shares, deadline, v, r, s);
        investmentManager.requestRedeem(address(this), shares, owner);
        emit RedeemRequest(owner, shares);
    }

    /// @notice Request decreasing the outstanding redemption orders. Will return the shares once the order
    ///         on Centrifuge is successfully decreased.
    function decreaseRedeemRequest(uint256 shares, address owner) public withApproval(owner) {
        investmentManager.decreaseRedeemRequest(address(this), shares, owner);
        emit DecreaseRedeemRequest(owner, shares);
    }

    /// @notice Request cancelling the outstanding redemption orders. Will return the shares once the order
    ///         on Centrifuge is successfully cancelled.
    function cancelRedeemRequest(address owner) public withApproval(owner) {
        investmentManager.cancelRedeemRequest(address(this), owner);
        emit CancelRedeemRequest(owner);
    }

    /// @notice View the total amount the user has requested to redeem but isn't able to withdraw or redeem yet
    function userRedeemRequest(address owner) external view returns (uint256 shares) {
        shares = investmentManager.userRedeemRequest(address(this), owner);
    }

    // --- ERC20 overrides ---
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

    function transferFrom(address, address, uint256) public returns (bool) {
        (bool success, bytes memory data) = address(share).call(bytes.concat(msg.data, bytes20(msg.sender)));
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    function transfer(address, uint256) public returns (bool) {
        (bool success, bytes memory data) = address(share).call(bytes.concat(msg.data, bytes20(msg.sender)));
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    function approve(address, uint256) public returns (bool) {
        (bool success, bytes memory data) = address(share).call(bytes.concat(msg.data, bytes20(msg.sender)));
        _successCheck(success);
        return abi.decode(data, (bool));
    }

    function mint(address, uint256) public auth {
        (bool success,) = address(share).call(bytes.concat(msg.data, bytes20(address(this))));
        _successCheck(success);
    }

    function burn(address, uint256) public auth {
        (bool success,) = address(share).call(bytes.concat(msg.data, bytes20(address(this))));
        _successCheck(success);
    }

    // --- Pricing ---
    function updatePrice(uint128 price) public auth {
        latestPrice = price;
        lastPriceUpdate = block.timestamp;
        emit PriceUpdate(price);
    }

    // --- Restriction overrides ---
    /// @notice Check if the shares are allowed to be transferred.
    function checkTransferRestriction(address from, address to, uint256 value) public view returns (bool) {
        return share.checkTransferRestriction(from, to, value);
    }

    // --- Helpers ---
    function _withPermit(
        address token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        try ERC20PermitLike(token).permit(owner, spender, value, deadline, v, r, s) {
            return;
        } catch {
            if (IERC20(token).allowance(owner, spender) >= value) {
                return;
            }
        }
        revert("LiquidityPool/permit-failure");
    }

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
