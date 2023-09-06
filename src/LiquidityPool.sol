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
    function processDeposit(address receiver, uint256 assets) external returns (uint256);
    function processMint(address receiver, uint256 shares) external returns (uint256);
    function processWithdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function processRedeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function maxDeposit(address user, address _tranche) external view returns (uint256);
    function maxMint(address user, address _tranche) external view returns (uint256);
    function maxWithdraw(address user, address _tranche) external view returns (uint256);
    function maxRedeem(address user, address _tranche) external view returns (uint256);
    function totalAssets(uint256 totalSupply, address liquidityPool) external view returns (uint256);
    function convertToShares(uint256 assets, address liquidityPool) external view returns (uint256);
    function convertToAssets(uint256 shares, address liquidityPool) external view returns (uint256);
    function previewDeposit(address user, address liquidityPool, uint256 assets) external view returns (uint256);
    function previewMint(address user, address liquidityPool, uint256 shares) external view returns (uint256);
    function previewWithdraw(address user, address liquidityPool, uint256 assets) external view returns (uint256);
    function previewRedeem(address user, address liquidityPool, uint256 shares) external view returns (uint256);
    function requestRedeem(uint256 shares, address receiver) external;
    function requestDeposit(uint256 assets, address receiver) external;
    function collectDeposit(address receiver) external;
    function collectRedeem(address receiver) external;
    function decreaseDepositRequest(uint256 assets, address receiver) external;
    function decreaseRedeemRequest(uint256 shares, address receiver) external;
}

/// @title  Liquidity Pool
/// @notice Liquidity Pool implementation for Centrifuge pools
///         following the EIP4626 standard, with asynchronous extension methods.
///
/// @dev    Each Liquidity Pool is a tokenized vault issuing shares of Centrifuge tranches as restricted ERC20 tokens against currency deposits based on the current share price.
///         This is extending the EIP4626 standard by 'requestRedeem' & 'requestDeposit' functions, where redeem and deposit orders are submitted to the pools
///         to be included in the execution of the following epoch. After execution users can use the deposit, mint, redeem and withdraw functions to
///         get their shares and/or assets from the pools.
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
    event DepositRequested(address indexed owner, uint256 assets);
    event RedeemRequested(address indexed owner, uint256 shares);
    event DepositCollected(address indexed owner);
    event RedeemCollected(address indexed owner);
    event UpdatePrice(uint128 price);

    constructor(uint64 poolId_, bytes16 trancheId_, address asset_, address share_, address investmentManager_) {
        poolId = poolId_;
        trancheId = trancheId_;
        asset = asset_;
        share = TrancheTokenLike(share_);
        investmentManager = InvestmentManagerLike(investmentManager_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev Either msg.sender is the owner or a ward on the contract
    modifier withApproval(address owner) {
        require((wards[msg.sender] == 1 || msg.sender == owner), "LiquidityPool/no-approval");
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
        return investmentManager.totalAssets(totalSupply(), address(this));
    }

    /// @notice Calculates the amount of shares that any user would approximately get for the amount of assets provided.
    ///         The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///         The actual conversion will likely differ as the price changes between order submission and execution.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = investmentManager.convertToShares(assets, address(this));
    }

    /// @notice Calculates the asset value for an amount of shares provided.
    ///         The calculation is based on the token price from the most recent epoch retrieved from Centrifuge.
    ///         The actual conversion will likely differ as the price changes between order submission and execution.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = investmentManager.convertToAssets(shares, address(this));
    }

    /// @return Maximum amount of assets that can be deposited into the Tranche by the receiver after the epoch had been executed on Centrifuge.
    function maxDeposit(address receiver) public view returns (uint256) {
        return investmentManager.maxDeposit(receiver, address(this));
    }

    /// @return shares that any user would get for an amount of assets provided
    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        shares = investmentManager.previewDeposit(msg.sender, address(this), assets);
    }

    /// @notice Collect shares for deposited assets after Centrifuge epoch execution.
    ///         maxDeposit is the max amount of shares that can be collected.
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = investmentManager.processDeposit(receiver, assets);
        emit Deposit(address(this), receiver, assets, shares);
    }

    /// @notice Collect shares for deposited assets after Centrifuge epoch execution.
    ///         maxMint is the max amount of shares that can be collected.
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        // require(receiver == msg.sender, "LiquidityPool/not-authorized-to-mint");
        assets = investmentManager.processMint(receiver, shares);
        emit Deposit(address(this), receiver, assets, shares);
    }

    /// @notice Maximum amount of shares that can be claimed by the receiver after the epoch has been executed on the Centrifuge side.
    function maxMint(address receiver) external view returns (uint256 maxShares) {
        maxShares = investmentManager.maxMint(receiver, address(this));
    }

    /// @return assets that any user would get for an amount of shares provided -> convertToAssets
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        assets = investmentManager.previewMint(msg.sender, address(this), shares);
    }

    /// @return maxAssets that the receiver can withdraw
    function maxWithdraw(address receiver) public view returns (uint256 maxAssets) {
        return investmentManager.maxWithdraw(receiver, address(this));
    }

    /// @return shares that a user would need to redeem in order to receive the given amount of assets -> convertToAssets
    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        shares = investmentManager.previewWithdraw(msg.sender, address(this), assets);
    }

    /// @notice Withdraw assets after successful epoch execution. Receiver will receive an exact amount of assets for a certain amount of shares that has been redeemed from Owner during epoch execution.
    /// @return shares that have been redeemed for the exact assets amount
    function withdraw(uint256 assets, address receiver, address owner)
        public
        withApproval(owner)
        returns (uint256 shares)
    {
        uint256 sharesRedeemed = investmentManager.processWithdraw(assets, receiver, owner);
        emit Withdraw(address(this), receiver, owner, assets, sharesRedeemed);
        return sharesRedeemed;
    }

    /// @notice Max amount of shares that can be redeemed by the owner after redemption was requested
    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        return investmentManager.maxRedeem(owner, address(this));
    }

    /// @return assets that any user could redeem for a given amount of shares
    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        assets = investmentManager.previewRedeem(msg.sender, address(this), shares);
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
        uint256 currencyPayout = investmentManager.processRedeem(shares, receiver, owner);
        emit Withdraw(address(this), receiver, owner, currencyPayout, shares);
        return currencyPayout;
    }

    // --- Asynchronous 4626 functions ---
    /// @notice Request asset deposit for a receiver to be included in the next epoch execution.
    /// @notice Request can only be called by the Owner of the assets or an authorized admin.
    ///         Asset is locked in the escrow on request submission
    function requestDeposit(uint256 assets, address owner) public withApproval(owner) {
        investmentManager.requestDeposit(assets, owner);
        emit DepositRequested(owner, assets);
    }

    /// @notice Similar to requestDeposit, but with a permit option.
    function requestDepositWithPermit(uint256 assets, address owner, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        ERC20PermitLike(asset).permit(owner, address(investmentManager), assets, deadline, v, r, s);
        investmentManager.requestDeposit(assets, owner);
        emit DepositRequested(owner, assets);
    }

    /// @notice Request share redemption for a receiver to be included in the next epoch execution.
    /// @notice Request can only be called by the Owner of the shares or an authorized admin.
    ///         Shares are locked in the escrow on request submission
    function requestRedeem(uint256 shares, address owner) public withApproval(owner) {
        investmentManager.requestRedeem(shares, owner);
        emit RedeemRequested(owner, shares);
    }

    /// @notice Similar to requestRedeem, but with a permit option.
    function requestRedeemWithPermit(uint256 shares, address owner, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        share.permit(owner, address(investmentManager), shares, deadline, v, r, s);
        investmentManager.requestRedeem(shares, owner);
        emit RedeemRequested(owner, shares);
    }

    /// @notice Request decreasing the outstanding deposit orders. Will return the assets once the order
    ///         on Centrifuge is successfully decreased.
    function decreaseDepositRequest(uint256 assets, address owner) public withApproval(owner) {
        investmentManager.decreaseDepositRequest(assets, owner);
    }

    /// @notice Request decreasing the outstanding redemption orders. Will return the shares once the order
    ///         on Centrifuge is successfully decreased.
    function decreaseRedeemRequest(uint256 shares, address owner) public withApproval(owner) {
        investmentManager.decreaseRedeemRequest(shares, owner);
    }

    // --- Miscellaneous investment functions ---
    /// @notice Trigger collecting the deposited funds.
    function collectDeposit(address receiver) public {
        investmentManager.collectDeposit(receiver);
        emit DepositCollected(receiver);
    }

    /// @notice Trigger collecting the deposited tokens.
    function collectRedeem(address receiver) public {
        investmentManager.collectRedeem(receiver);
        emit RedeemCollected(receiver);
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
        emit UpdatePrice(price);
    }

    // --- Restriction overrides ---
    /// @notice Check if the shares are allowed to be transferred.
    function checkTransferRestriction(address from, address to, uint256 value) public view returns (bool) {
        return share.checkTransferRestriction(from, to, value);
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
