// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import "./../auth/auth.sol";

interface TrancheTokenLike {
    // erc20 functions
    function mint(address owner, uint256 amount) external;
    function burn(address owner, uint256 amount) external;

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    // function approve(address spender, uint256 amount) external returns (bool);
    function approveForOwner(address owner, address spender, uint256 value) external returns (bool);

    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function allowance(address owner, address spender) external returns (uint256);
    // function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    // function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function increaseAllowanceForOwner(address owner, address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowanceForOwner(address owner, address spender, uint256 subtractedValue)
        external
        returns (bool);

    // restricted token functions
    function latestPrice() external view returns (uint256);
    function memberlist() external returns (address);
    function hasMember(address) external returns (bool);
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
    function requestRedeem(uint256 shares, address receiver) external;
    function requestDeposit(uint256 assets, address receiver) external;
    function collectInvest(uint64 poolId, bytes16 trancheId, address receiver, address currency) external;
    function collectRedeem(uint64 poolId, bytes16 trancheId, address receiver, address currency) external;
}

/// @title LiquidityPool
/// @author ilinzweilin
/// @dev Liquidity Pool implementation for Centrifuge Pools following the EIP4626 standard.
///
/// @notice Each Liquidity Pool is a tokenized vault issuing shares as restricted ERC20 tokens against currency deposits based on the current share price.
/// This is extending the EIP4626 standard by 'requestRedeem' & 'requestDeposit' functions, where redeem and deposit orders are submitted to the pools
/// to be included in the execution of the following epoch. After execution users can use the redeem and withdraw functions to get their shares and/or assets from the pools.
contract LiquidityPool is Auth {
    InvestmentManagerLike public investmentManager;

    /// @notice asset: The underlying stable currency of the Liquidity Pool. Note: 1 Centrifuge Pool can have multiple Liquidity Pools for the same Tranche token with different underlying currencies (assets).
    address public asset;

    /// @notice share: The restricted ERC-20 Liquidity pool token. Has a ratio (token price) of underlying assets exchanged on deposit/withdraw/redeem. Liquidity pool tokens on evm represent tranche tokens on centrifuge chain (even though in the current implementation one tranche token on centrifuge chain can be split across multiple liquidity pool tokens on EVM).
    TrancheTokenLike public share;

    uint64 public poolId;
    bytes16 public trancheId;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @dev investmentManager and asset address to be filed by the factory on deployment
    function file(bytes32 what, address data) public auth {
        if (what == "investmentManager") investmentManager = InvestmentManagerLike(data);
        else if (what == "asset") asset = data;
        else if (what == "share") share = TrancheTokenLike(data);
        else revert("LiquidityPool/file-unrecognized-param");
        emit File(what, data);
    }

    /// @dev Centrifuge chain pool information to be filed by factory on deployment
    function setPoolDetails(uint64 _poolId, bytes16 _trancheId) public auth {
        require(poolId == 0, "LiquidityPool/pool-details-already-set");
        poolId = _poolId;
        trancheId = _trancheId;
    }

    // --- ERC4626 functions ---
    /// @dev The total amount of vault shares
    /// @return Total amount of the underlying vault assets including accrued interest
    function totalAssets() public view returns (uint256) {
        return totalSupply() * latestPrice();
    }

    /// @dev Calculates the amount of shares / tranche tokens that any user would get for the amount of assets provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = assets / latestPrice();
    }

    /// @dev Calculates the asset value for an amount of shares / tranche tokens provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = shares * latestPrice();
    }

    /// @return Maximum amount of stable currency that can be deposited into the Tranche by the receiver after the epoch had been executed on Centrifuge chain.
    function maxDeposit(address receiver) public view returns (uint256) {
        return investmentManager.maxDeposit(receiver, address(this));
    }

    /// @return shares that any user would get for an amount of assets provided -> convertToShares
    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    /// @dev request asset deposit for a receiver to be included in the next epoch execution. Asset is locked in the escrow on request submission
    function requestDeposit(uint256 assets) public {
        investmentManager.requestDeposit(assets, msg.sender);
    }

    /// @dev collect shares for deposited funds after pool epoch execution. maxMint is the max amount of shares that can be collected. Required assets must already be locked
    /// maxDeposit is the amount of funds that was successfully invested into the pool on Centrifuge chain
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = investmentManager.processDeposit(receiver, assets);
        emit Deposit(address(this), receiver, assets, shares);
    }

    /// @dev collect shares for deposited funds after pool epoch execution. maxMint is the max amount of shares that can be collected. Required assets must already be locked
    /// maxDeposit is the amount of funds that was successfully invested into the pool on Centrifuge chain
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        // require(receiver == msg.sender, "LiquidityPool/not-authorized-to-mint");
        assets = investmentManager.processMint(receiver, shares);
        emit Deposit(address(this), receiver, assets, shares);
    }

    /// @dev Maximum amount of shares that can be claimed by the receiver after the epoch has been executed on the Centrifuge chain side.
    function maxMint(address receiver) external view returns (uint256 maxShares) {
        maxShares = investmentManager.maxMint(receiver, address(this));
    }

    /// @return assets that any user would get for an amount of shares provided -> convertToAssets
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /// @dev request share redemption for a receiver to be included in the next epoch execution. Shares are locked in the escrow on request submission
    function requestRedeem(uint256 shares) public {
        investmentManager.requestRedeem(shares, msg.sender);
    }

    /// @return maxAssets that the receiver can withdraw
    function maxWithdraw(address receiver) public view returns (uint256 maxAssets) {
        return investmentManager.maxWithdraw(receiver, address(this));
    }

    /// @return shares that a user would need to redeem in order to receive the given amount of assets -> convertToAssets
    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    /// @dev Withdraw assets after successful epoch execution. Receiver will receive an exact amount of assets for a certain amount of shares that has been redeemed from Owner during epoch execution.
    /// @return shares that have been redeemed for the excat assets amount
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        // check if messgae sender can spend owners funds
        require(owner == msg.sender, "LiquidityPool/not-authorized-to-withdraw");
        uint256 sharesRedeemed = investmentManager.processWithdraw(assets, receiver, owner);
        emit Withdraw(address(this), receiver, owner, assets, sharesRedeemed);
        return sharesRedeemed;
    }

    /// @dev Max amount of shares that can be redeemed by the owner after redemption was requested
    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        return investmentManager.maxRedeem(owner, address(this));
    }

    /// @return assets that any user could redeem for an given amount of shares -> convertToAssets
    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /// @dev Redeem shares after successful epoch execution. Receiver will receive assets for the exact amount of redeemed shares from Owner after epoch execution.
    /// @return assets currency payout for the exact amount of redeemed shares
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        require(owner == msg.sender, "LiquidityPool/not-authorized-to-redeem");
        uint256 currencyPayout = investmentManager.processRedeem(shares, receiver, owner);
        emit Withdraw(address(this), receiver, owner, currencyPayout, shares);
        return currencyPayout;
    }

    function collectRedeem(address receiver) public {
        investmentManager.collectRedeem(poolId, trancheId, receiver, asset);
    }

    function collectInvest(address receiver) public {
        investmentManager.collectInvest(poolId, trancheId, receiver, asset);
    }

    // --- ERC20 overrides ---
    function totalSupply() public view returns (uint256) {
        return share.totalSupply();
    }

    function balanceOf(address owner) public returns (uint256) {
        return share.balanceOf(owner);
    }

    function transfer(address recipient, uint256 amount) public auth returns (bool) {
        return share.transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public auth returns (bool) {
        return share.transferFrom(sender, recipient, amount);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        return share.approveForOwner(msg.sender, spender, amount);
    }

    function increaseAllowance(address spender, uint256 _addedValue) public returns (bool) {
        return share.increaseAllowanceForOwner(msg.sender, spender, _addedValue);
    }

    function decreaseAllowance(address spender, uint256 _subtractedValue) public returns (bool) {
        return share.decreaseAllowanceForOwner(msg.sender, spender, _subtractedValue);
    }

    function mint(address owner, uint256 amount) public auth {
        share.mint(owner, amount);
    }

    function burn(address owner, uint256 amount) public auth {
        share.burn(owner, amount);
    }

    function allowance(address owner, address spender) public returns (uint256) {
        return share.allowance(owner, spender);
    }

    // --- Restrictions ---
    function latestPrice() public view returns (uint256) {
        return share.latestPrice();
    }

    function hasMember(address user) public returns (bool) {
        return share.hasMember(user);
    }
}
