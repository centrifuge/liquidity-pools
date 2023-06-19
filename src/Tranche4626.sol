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
// Tranche4626 is extending the EIP4626 standard by 'requestRedeem' & 'requestDeposit' functions, where redeem and deposit orders are submitted to the pools to be included in the execution of the following epoch.
// After execution users can use the redeem and withdraw functions to get their shares and/or assets from the pools.

// other EIP4626 implementations
// maple: https://github.com/maple-labs/pool-v2/blob/301f05b4fe5e9202eef988b4c8321310b4e86dc8/contracts/Pool.sol
// yearn: https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy



// create deposit flow in connectors
// create mint flow
// create redeem flow
// create withdraw flow 
// messages collectRedeem & collectInvest


import "./token/restricted.sol";

interface ConnectorLike {
    function deposit(uint64 _poolId, address _tranche, address _receiver, uint256 _assets) external returns (uint256);
    function mint(uint64 _poolId, address _tranche, address _receiver, uint256 _shares) external returns (uint256);
    function maxDeposit(address _user, address _tranche) external returns (uint256);
    function maxMint(address _user, address _tranche) external returns (uint256);
    function maxWithdraw(address _user, address _tranche) external returns (uint256);
    function maxRedeem(address _user, address _tranche) external returns (uint256) 
}

/// @title Tranche4626
/// @author ilinzweilin
contract Tranche4626 is RestrictedToken {

    ConnectorLike public connector;

    address public asset; // underlying stable ERC-20 stable currency.
    uint256 public maxAssetDeposit = 2 ** 256 - 1; // max stable currency deposit into the tranche -> default: no limit.
    uint64 public poolId; // the id of the Centrifuge pool the Tranche belongs to.
    bytes16 trancheId; // the trancheId valid across all chains. 

    uint128 latestPrice; // lates share / token price 
    uint256 lastPriceUpdate; // timestamp of the latest share / token price update
   
    // ERC4626 events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    
    constructor(address _asset, bytes16 _trancheId, uint64 _poolId, address _connector) {
        asset = _asset;
        trancheId = _trancheId;
        poolId = _poolId;
        connector = ConnectorLike(_connector);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev The total amount of vault shares.
    /// @return Total amount of the underlying vault assets including accrued interest.
    function totalAssets() public view returns (uint256) {
       return totalSupply() * latestPrice; 
    }

    /// @dev Calculates the amount of shares / tranche tokens that any user would get for the amount of assets provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToShares(uint256 _assets) public view returns (uint256 shares) {
        // TODO: it should round DOWN if it’s calculating the amount of shares to issue to a user, given an amount of assets provided.
        shares = _assets / latestPrice;
    }

    /// @dev Calculates the asset value for an amount of shares / tranche tokens provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToAssets(uint256 _shares) public view returns (uint256 assets) {
        // TODO: it should round DOWN if it’s calculating the amount of assets to issue to a user, given an amount of shares provided.
        assets = _shares * latestPrice;
    }

    /// @return Maximum amount of stable currency that can be deposited into the Tranche by the receiver after the epoch had been executed on Centrifuge chain.
    function maxDeposit(address _receiver) public view returns (uint256) {
        return connector.maxDeposit(_receiver, address(this));
    }

    /// @return The amount of shares that any user would get for an amount of assets provided -> convertToShares
    function previewDeposit(uint256 _assets) public view returns (uint256 shares) {
        shares = convertToShares(_assets);
    }

    /// @dev request asset deposit for a receiver to be included in the next epoch execution. Asset is locked in the escrow on request submission.
    function requestDeposit(uint256 _assets, address _receiver) auth public {
    }

    /// @dev collect shares for deposited funds after pool epoch execution. maxMint is the max amount of shares that can be collected. Required assets must already be locked.
    /// maxDeposit is the amount of funds that was successfully invested into the pool on Centrifuge chain
    function deposit(uint256 _assets, address _receiver)  auth public returns (uint256 shares) {
        uint transferredShares = connector.deposit(poolId, address(this), _receiver, _assets);
        Deposit(address(this), _receiver, _assets, transferredShares);
    }

    /// @dev collect shares for deposited funds after pool epoch execution. maxMint is the max amount of shares that can be collected. Required assets must already be locked.
    /// maxDeposit is the amount of funds that was successfully invested into the pool on Centrifuge chain
    function mint(uint256 _shares, address _receiver)  auth public returns (uint256 assets) {
      uint lockedAssets = connector.mint(poolId, address(this), _receiver, _shares); 
      Deposit(address(this), _receiver, lockedAssets, _shares);
    }

    /// @dev Maximum amount of shares that can be claimed by the receiver after the epoch has been executed on the Centrifuge chain side.
    function maxMint(address receiver) external view returns (uint256 maxShares) {
        return connector.maxMint(_receiver, address(this));
    }

    /// @return The amount of assets that any user would get for an amount of shares provided -> convertToAssets
    function previewMint(uint256 _shares) external view returns (uint256 assets) {
        assets = convertToAssets(_shares);
    }

    /// @dev 
    /// @return
    function maxWithdraw(address _owner) external view returns (uint256 maxAssets) {
        return connector.maxWithdraw(_owner, address(this));
    }
    /// @dev 
    /// @return
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    /// @dev 
    /// @return
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    /// @dev 
    /// @return
    function maxRedeem(address owner) external view returns (uint256 maxShares) {
         return connector.maxRedeem(_owner, address(this));
    }
    
    /// @dev 
    /// @return
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    /// @dev 
    /// @return
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    function updateTokenPrice(uint128 _tokenPrice) public auth {
        latestPrice = _tokenPrice;
        lastPriceUpdate = block.timestamp;
    }

   function updateTotalAssets(uint128 _tokenPrice) public auth {
        latestPrice = _tokenPrice;
        lastPriceUpdate = block.timestamp;
    }




}
