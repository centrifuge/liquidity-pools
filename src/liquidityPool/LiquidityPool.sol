// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import "./../auth/auth.sol";

interface RestrictedTokenERC20 { 
    // erc20 functions
    function mint(address owner, uint256 amount) external;
    function burn(address owner, uint256 amount) external;
   
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    // function approve(address spender, uint256 amount) external returns (bool);
    function approveForOwner(address owner, address spender, uint256 value) external returns (bool);
   
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function allowance(address owner, address spender)  external returns (uint256);
    // function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    // function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function increaseAllowanceForOwner(address owner, address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowanceForOwner(address owner, address spender, uint256 subtractedValue) external returns (bool);

     // restricted token functions
    function latestPrice() external view returns (uint256);
    function memberlist() external returns (address);
    function hasMember(address) external returns (bool);
}


// Liquidity Pool implementation for Centrifuge Pools following the EIP4626 standard.
// Each Liquidity Pool is a tokenized vault issuing shares as restricted ERC20 tokens against stable currency deposits based on the current share price.
// Liquidity Pool vault: Liquidity Pool asset value.
// asset: The underlying stable currency of the Liquidity Pool. Note: 1 Centrifuge Pool can have multiple Liquidity Pools for the same Tranche token with different underlying currencies (assets).
// share: The restricted ERC-20 Liquidity pool token. Has a ratio (token price) of underlying assets exchanged on deposit/withdraw/redeem. Liquidity pool tokens on evm represent tranche tokens on centrifuge chain (even though in the current implementation one tranche token on centrifuge chain can be split across multiple liquidity pool tokens on EVM).

// Challenges:
// 1. Centrifuge Pools and corresponding Tranches live on Centchain having their liquidity spread across multiple chains.
// Latest Tranche Token token price is not available in the same block and is updated in an async manner from Centrifuge chain. Deposit & Redemption previews can only be made based on the latest price updates from Centrifuge chain.
// 2. Pool Epochs: Deposits into and redemptions from Centrifuge Pools are subject to epochs. Deposit and redemption orders are collected during 24H epoch periods
// and filled during epoch execution following the rules of the underlying pool. Consequently, deposits and redemptions are not instanty possible and have to follow the epoch schedule.
// LiquidityPool is extending the EIP4626 standard by 'requestRedeem' & 'requestDeposit' functions, where redeem and deposit orders are submitted to the pools to be included in the execution of the following epoch.
// After execution users can use the redeem and withdraw functions to get their shares and/or assets from the pools.

// other EIP4626 implementations
// maple: https://github.com/maple-labs/pool-v2/blob/301f05b4fe5e9202eef988b4c8321310b4e86dc8/contracts/Pool.sol
// yearn: https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy

interface InvestmentManagerLike {
    function processDeposit(address _receiver, uint256 _assets) external returns (uint256);
    function processMint(address _receiver, uint256 _shares) external returns (uint256);
    function processWithdraw(uint256 _assets, address _receiver, address _owner) external returns (uint256);
    function processRedeem(uint256 _shares, address _receiver, address _owner) external returns (uint256);
    function maxDeposit(address _user, address _tranche) external view returns (uint256);
    function maxMint(address _user, address _tranche) external view returns (uint256);
    function maxWithdraw(address _user, address _tranche) external view returns (uint256);
    function maxRedeem(address _user, address _tranche) external view returns (uint256);
    function requestRedeem(uint256 _shares, address _receiver) external;
    function requestDeposit(uint256 _assets, address _receiver) external;
    function collectInvest(uint64 poolId, bytes16 trancheId, address receiver, address currency) external;
    function collectRedeem(uint64 poolId, bytes16 trancheId, address receiver, address currency) external;
}

/// @title LiquidityPool
/// @author ilinzweilin
/// @dev LiquidityPool is compliant with the EIP4626 & ERC20 standards
contract LiquidityPool is Auth {
    InvestmentManagerLike public investmentManager;

    address public asset; // underlying stable ERC-20 stable currency
    RestrictedTokenERC20 public share; // underlying trache Token

    // ids of the existing centrifuge chain pool and tranche that the liquidity pool belongs to
    uint64 public poolId;
    bytes16 public trancheId;

    // events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares );
    event File(bytes32 indexed what, address data);

    constructor() {
        wards[msg.sender] = 1;
    }

    /// @dev investmentManager and asset address to be filed by the factory on deployment
    function file(bytes32 _what, address _data) public auth {
        if (_what == "investmentManager") investmentManager = InvestmentManagerLike(_data);
        else if (_what == "asset") asset = _data;
        else if (_what == "share") share = RestrictedTokenERC20(_data);
        else revert("LiquidityPool/file-unrecognized-param");
        emit File(_what, _data);
    }

    /// @dev Centrifuge chain pool information to be filed by factory on deployment
    function setPoolDetails(uint64 _poolId, bytes16 _trancheId) public auth {
        require(poolId == 0, "LiquidityPool/pool-details-already-set");
        poolId = _poolId;
        trancheId = _trancheId;
    }

    /// @dev The total amount of vault shares
    /// @return Total amount of the underlying vault assets including accrued interest
    function totalAssets() public view returns (uint256) {
        return totalSupply() * latestPrice();
    }

    /// @dev Calculates the amount of shares / tranche tokens that any user would get for the amount of assets provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToShares(uint256 _assets) public view returns (uint256 shares) {
        shares = _assets / latestPrice();
    }

    /// @dev Calculates the asset value for an amount of shares / tranche tokens provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToAssets(uint256 _shares) public view returns (uint256 assets) {
        assets = _shares * latestPrice();
    }

    /// @return Maximum amount of stable currency that can be deposited into the Tranche by the receiver after the epoch had been executed on Centrifuge chain.
    function maxDeposit(address _receiver) public view returns (uint256) {
        return investmentManager.maxDeposit(_receiver, address(this));
    }

    /// @return shares that any user would get for an amount of assets provided -> convertToShares
    function previewDeposit(uint256 _assets) public view returns (uint256 shares) {
        shares = convertToShares(_assets);
    }

    /// @dev request asset deposit for a receiver to be included in the next epoch execution. Asset is locked in the escrow on request submission
    function requestDeposit(uint256 _assets) public {
        investmentManager.requestDeposit(_assets, msg.sender);
    }

    /// @dev collect shares for deposited funds after pool epoch execution. maxMint is the max amount of shares that can be collected. Required assets must already be locked
    /// maxDeposit is the amount of funds that was successfully invested into the pool on Centrifuge chain
    function deposit(uint256 _assets, address _receiver) public returns (uint256 shares) {
        shares = investmentManager.processDeposit(_receiver, _assets);
        emit Deposit(address(this), _receiver, _assets, shares);
    }

    /// @dev collect shares for deposited funds after pool epoch execution. maxMint is the max amount of shares that can be collected. Required assets must already be locked
    /// maxDeposit is the amount of funds that was successfully invested into the pool on Centrifuge chain
    function mint(uint256 _shares, address _receiver) public returns (uint256 assets) {
        // require(_receiver == msg.sender, "LiquidityPool/not-authorized-to-mint");
        assets = investmentManager.processMint(_receiver, _shares);
        emit Deposit(address(this), _receiver, assets, _shares);
    }

    /// @dev Maximum amount of shares that can be claimed by the receiver after the epoch has been executed on the Centrifuge chain side.
    function maxMint(address _receiver) external view returns (uint256 maxShares) {
        maxShares = investmentManager.maxMint(_receiver, address(this));
    }

    /// @return assets that any user would get for an amount of shares provided -> convertToAssets
    function previewMint(uint256 _shares) external view returns (uint256 assets) {
        assets = convertToAssets(_shares);
    }

    /// @dev request share redemption for a receiver to be included in the next epoch execution. Shares are locked in the escrow on request submission
    function requestRedeem(uint256 _shares) public {
        investmentManager.requestRedeem(_shares, msg.sender);
    }

    /// @return maxAssets that the receiver can withdraw
    function maxWithdraw(address _receiver) public view returns (uint256 maxAssets) {
        return investmentManager.maxWithdraw(_receiver, address(this));
    }

    /// @return shares that a user would need to redeem in order to receive the given amount of assets -> convertToAssets
    function previewWithdraw(uint256 _assets) public view returns (uint256 shares) {
        shares = convertToShares(_assets);
    }

    /// @dev Withdraw assets after successful epoch execution. Receiver will receive an exact amount of _assets for a certain amount of shares that has been redeemed from Owner during epoch execution.
    /// @return shares that have been redeemed for the excat _assets amount
    function withdraw(uint256 _assets, address _receiver, address _owner) public returns (uint256 shares) {
        // check if messgae sender can spend owners funds
        require(_owner == msg.sender, "LiquidityPool/not-authorized-to-withdraw");
        uint256 sharesRedeemed = investmentManager.processWithdraw(_assets, _receiver, _owner);
        emit Withdraw(address(this), _receiver, _owner, _assets, sharesRedeemed);
        return sharesRedeemed;
    }

    /// @dev Max amount of shares that can be redeemed by the owner after redemption was requested
    function maxRedeem(address _owner) public view returns (uint256 maxShares) {
        return investmentManager.maxRedeem(_owner, address(this));
    }

    /// @return assets that any user could redeem for an given amount of shares -> convertToAssets
    function previewRedeem(uint256 _shares) public view returns (uint256 assets) {
        assets = convertToAssets(_shares);
    }

    /// @dev Redeem shares after successful epoch execution. Receiver will receive assets for the exact amount of redeemed shares from Owner after epoch execution.
    /// @return assets currency payout for the exact amount of redeemed _shares
    function redeem(uint256 _shares, address _receiver, address _owner) public returns (uint256 assets) {
        require(_owner == msg.sender, "LiquidityPool/not-authorized-to-redeem");
        uint256 currencyPayout = investmentManager.processRedeem(_shares, _receiver, _owner);
        emit Withdraw(address(this), _receiver, _owner, currencyPayout, _shares);
        return currencyPayout;
    }

    function collectRedeem(address _receiver) public {
        investmentManager.collectRedeem(poolId, trancheId, _receiver, asset);
    }

    function collectInvest(address _receiver) public {
        investmentManager.collectInvest(poolId, trancheId, _receiver, asset);
    }

    // overwrite all ERC20 functions and pass the calls to the shares contract
    function totalSupply() public view returns (uint256) {
        return share.totalSupply();
    }

    function balanceOf(address _owner) public returns (uint256) {
         return share.balanceOf(_owner);
    }

    function transfer(address _recipient, uint256 _amount) public returns (bool) {
        return share.transferFrom(msg.sender, _recipient, _amount);   
    }

    // test allowance
    function transferFrom(address _sender, address _recipient, uint256 _amount) public returns (bool) {
        return share.transferFrom(_sender, _recipient, _amount);   
    }

    function approve(address _spender, uint256 _amount) public returns (bool) { 
        return share.approveForOwner(msg.sender, _spender, _amount);
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
        return share.increaseAllowanceForOwner(msg.sender, _spender, _addedValue); 
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
        return share.decreaseAllowanceForOwner(msg.sender, _spender, _subtractedValue); 
    }

    function mint(address _owner, uint256 _amount) auth public {
        share.mint(_owner, _amount);
    }

    function burn(address _owner, uint256 _amount) auth public {
        share.burn(_owner, _amount);
    }

    function allowance(address _owner, address _spender) public returns (uint256) {
        return share.allowance(_owner, _spender);
    }

    // restricted token functions

    function latestPrice() public view returns (uint256) {
        return share.latestPrice();  
    }

    function hasMember(address _user) public returns (bool) {
        return share.hasMember(_user);
    }
}
