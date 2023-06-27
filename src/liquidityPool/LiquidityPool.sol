// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

// Tranche implementation for Centrifuge Pools following the EIP4626 standard. 
// Each Tranche is a tokenized vault issuing shares as restricted ERC20 tokens against stable currency deposits based on the current share price.
// tranche vault: tranche asset value.
// asset: The underlying stable currency of the Centrifuge pool. 
// share: The restricted ERC-20 Tranche token (TIN/DROP). Has a ratio (token price) of underlying assets exchanged on deposit/withdraw/redeem

// Challenges: 
// 1. Centrifuge Pools and corresponding Tranches live on Centchain having their liquidity spread across multiple chains. 
// Latest Tranche values, like share / token price, tranche asset value, total assets... have to be retrieved from Centrifuge chain in order to provide share <-> asset conversions.
// 2. Pool Epochs: Deposits into and redemptions from Centrifuge Pools are subject to epochs. Deposit and redemption orders are collected during 24H epoch periods
// and filled during epoch execution following the rules of the underlying pool. Consequently, deposits and redemptions are not instanty possible and have to follow the epoch schedule. 
// LiquidityPool is extending the EIP4626 standard by 'requestRedeem' & 'requestDeposit' functions, where redeem and deposit orders are submitted to the pools to be included in the execution of the following epoch.
// After execution users can use the redeem and withdraw functions to get their shares and/or assets from the pools.

// other EIP4626 implementations
// maple: https://github.com/maple-labs/pool-v2/blob/301f05b4fe5e9202eef988b4c8321310b4e86dc8/contracts/Pool.sol
// yearn: https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy


import "../token/restricted.sol";

interface ConnectorLike {
    function processDeposit(address _receiver, uint256 _assets) external returns (uint256);
    function processMint(address _receiver, uint256 _shares) external returns (uint256);
    function processWithdraw(uint256 _assets, address _receiver, address _owner) external returns (uint256);
    function maxDeposit(address _user, address _tranche) external view returns (uint256);
    function maxMint(address _user, address _tranche) external view returns (uint256);
    function maxWithdraw(address _user, address _tranche) external view returns (uint256);
    function maxRedeem(address _user, address _tranche) external view returns (uint256);
    function requestRedeem(uint256 _shares, address _receiver) external;
    function requestDeposit(uint256 _assets, address _receiver) external;
    
}

/// @title LiquidityPool
/// @author ilinzweilin
contract LiquidityPool is RestrictedToken {

    ConnectorLike public connector;

    address public asset; // underlying stable ERC-20 stable currency

    uint128 public latestPrice; // share price
    uint256 public lastPriceUpdate; // timestamp of the latest share price update

    // ids of the existing centrifuge chain pool and tranche that the liquidity pool belongs to
    uint64 public poolId;
    bytes16 public trancheId;
   
    // events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    
    constructor(uint8 _decimals) RestrictedToken(_decimals) {}

    /// @dev connector and asset address to be filed by the factory on deployment
    function file(bytes32 _what, address _data) override public auth {
        if (_what == "connector") connector = ConnectorLike(_data);
        else if (_what == "asset") asset = _data;
        else if (_what == "memberlist") memberlist = MemberlistLike(_data);
        else revert("LiquidityPool/file-unrecognized-param");
        emit File(_what, _data);
    }

    /// @dev Centrifuge chain pool information to be files by factory on deployment
    function setPoolDetails(uint64 _poolId, bytes16 _trancheId) public auth {
        require(poolId == 0, "LiquidityPool/pool-details-already-set");
        poolId = _poolId;
        trancheId = _trancheId;
    }

    /// @dev The total amount of vault shares
    /// @return Total amount of the underlying vault assets including accrued interest
    function totalAssets() public view returns (uint256) {
       return totalSupply * latestPrice; 
    }

    /// @dev Calculates the amount of shares / tranche tokens that any user would get for the amount of assets provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToShares(uint256 _assets) public view returns (uint256 shares) {
        shares = _assets / latestPrice;
    }

    /// @dev Calculates the asset value for an amount of shares / tranche tokens provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToAssets(uint256 _shares) public view returns (uint256 assets) {
        assets = _shares * latestPrice;
    }

    /// @return Maximum amount of stable currency that can be deposited into the Tranche by the receiver after the epoch had been executed on Centrifuge chain.
    function maxDeposit(address _receiver) public view returns (uint256) {
        return connector.maxDeposit(_receiver, address(this));
    }

    /// @return shares that any user would get for an amount of assets provided -> convertToShares
    function previewDeposit(uint256 _assets) public view returns (uint256 shares) {
        shares = convertToShares(_assets);
    }

    /// @dev request asset deposit for a receiver to be included in the next epoch execution. Asset is locked in the escrow on request submission
    function requestDeposit(uint256 _assets, address _receiver) auth public {
        connector.requestDeposit(_assets, _receiver);
    }

    /// @dev collect shares for deposited funds after pool epoch execution. maxMint is the max amount of shares that can be collected. Required assets must already be locked
    /// maxDeposit is the amount of funds that was successfully invested into the pool on Centrifuge chain
    function deposit(uint256 _assets, address _receiver)  auth public returns (uint256 shares) {
        shares = connector.processDeposit( _receiver, _assets);
        emit Deposit(address(this), _receiver, _assets, shares);
    }

    /// @dev collect shares for deposited funds after pool epoch execution. maxMint is the max amount of shares that can be collected. Required assets must already be locked
    /// maxDeposit is the amount of funds that was successfully invested into the pool on Centrifuge chain
    function mint(uint256 _shares, address _receiver) auth public returns (uint256 assets) {
        assets = connector.processMint(_receiver, _shares); 
        emit Deposit(address(this), _receiver, assets, _shares);
    }

    /// @dev Maximum amount of shares that can be claimed by the receiver after the epoch has been executed on the Centrifuge chain side.
    function maxMint(address _receiver) external view returns (uint256 maxShares) {
         maxShares = connector.maxMint(_receiver, address(this));
    }

    /// @return assets that any user would get for an amount of shares provided -> convertToAssets
    function previewMint(uint256 _shares) external view returns (uint256 assets) {
        assets = convertToAssets(_shares);
    }

    /// @dev request share redemption for a receiver to be included in the next epoch execution. Shares are locked in the escrow on request submission
    function requestRedeem(uint256 _shares, address _receiver) auth public {
        connector.requestRedeem(_shares, _receiver);
    }

    /// @return maxAssets that the receiver can withdraw
    function maxWithdraw(address _receiver) public view returns (uint256 maxAssets) {
        return connector.maxWithdraw(_receiver, address(this));
    }
    
    /// @return shares that a user would need to redeem in order to receive the given amount of assets -> convertToAssets
    function previewWithdraw(uint256 _assets) public view returns (uint256 shares) {
        shares = convertToShares(_assets);
    }

    /// @dev Withdraw assets after successful epoch execution. Receiver will receive an exact amount of _assets for a certain amount of shares that has been redeemed from Owner during epoch execution.
    /// @return shares that have been redeemed for the excat _assets amount
    function withdraw(uint256 _assets, address _receiver, address _owner) auth public returns (uint256 shares) {
        uint sharesRedeemed = connector.processWithdraw( _assets, _receiver, _owner);
        emit Withdraw(address(this), _receiver, _owner, _assets, sharesRedeemed);
        return sharesRedeemed;
    }

    /// @dev Max amount of shares that can be redeemed by the owner after redemption was requested
    function maxRedeem(address _owner) public view returns (uint256 maxShares) {
         return connector.maxRedeem(_owner, address(this));
    }

    /// @return assets that any user could redeem for an given amount of shares -> convertToAssets
    function previewRedeem(uint256 _shares) public view returns (uint256 assets) {
        assets = convertToAssets(_shares);
    }

    /// @dev Redeem shares after successful epoch execution. Receiver will receive assets for the exact amount of redeemed shares from Owner after epoch execution.
    /// @return assets currency payout for the exact amount of redeemed _shares
    function redeem(uint256 _shares, address _receiver, address _owner) auth public returns (uint256 assets) {
        uint currencyPayout = connector.processWithdraw(_shares, _receiver, _owner);
        emit Withdraw(address(this), _receiver, _owner, currencyPayout, _shares);
        return currencyPayout;
    }

    // auth functions
    function updateTokenPrice(uint128 _tokenPrice) public auth {
        latestPrice = _tokenPrice;
        lastPriceUpdate = block.timestamp;
    }
}
