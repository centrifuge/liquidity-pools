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

import "./token/restricted.sol";

interface GatewayLike {
    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        external;
    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        external;
    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        external;
    function decreaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        external;
    function collectInvest(uint64 poolId, bytes16 trancheId, address investor) external;
    function collectRedeem(uint64 poolId, bytes16 trancheId, address investor) external;
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

/// @title Tranche4626
/// @author ilinzweilin
contract Tranche4626 is RestrictedToken {

    EscrowLike public immutable escrow;
    GatewayLike public gateway;

    address public asset; // underlying stable ERC-20 stable currency
    uint256 public maxAssetDeposit = 2 ** 256 - 1; // max stable currency deposit into the tranche -> default: no limit.
    uint64 public poolId; // the id of the Centrifuge pool the Tranche belongs to.
    bytes16 trancheId; // the trancheId valid across all chains. 


    uint128 latestPrice; // lates share / token price 
    uint256 lastPriceUpdate; // timestamp of the latest share / token price update
    //TODO: retrieve from Centrifuge chain.
    uint256 lastTotalAssets; // latest asset value of the tranche retrieved from the Centrifuge chain
    uint256 lastTotalAssetsUpdate; // timestamp of the latest total assets update


    // ERC4626 events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    
    constructor(address _asset, bytes16 _trancheId, uint64 _poolId, address _gateway, address _escrow) {
        asset = _asset;
        trancheId = _trancheId;
        poolId = _poolId;
        gateway = gateway;
        escrow = _escrow;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev The total amount of the undelying assets = the asset value of the tranche retrieved from the Centrifuge chain.
    /// @return Total amount of the underlying assets that is managed by Tranche including accrued interest.
    function totalAssets() public view returns (uint256) {
        return lastTotalAssets;
    }

    /// @dev The latest share price is retrieved from the Centrifuge chain.
    /// @return The amount of shares / tranche tokens that any user would get for the amount of assets provided.
    function convertToShares(uint256 _assets) public view returns (uint256 shares) {
        // TODO: it should round DOWN if it’s calculating the amount of shares to issue to a user, given an amount of assets provided.
        shares = _assets / latestPrice;
    }

    /// @dev The latest share price is retrieved from the Centrifuge chain.
    /// @return The amount of assets that any user would get for the amount of shares provided.
    function convertToAssets(uint256 _shares) public view returns (uint256 assets) {
        // TODO: it should round DOWN if it’s calculating the amount of assets to issue to a user, given an amount of shares provided.
        assets = _shares * latestPrice;
    }

    /// TODO: do we need to have a custom limit for each receiver?
    /// @dev return 0 if deposits are disabled, or 2 ** 256 - 1 if there is no limit. 
    /// @return Maximum amount of stable currency that can be deposited into the Tranche by the receiver.
    function maxDeposit(address _receiver) public view returns (uint256) {
        return maxAssetDeposit;
    }

    /// TODO: should we run some pool checks that would cause deposit to revert?
    /// @return The amount of assets that any user would get for the amount of shares provided -> convertToShares
    function previewDeposit(uint256 _assets) public view returns (uint256 shares) {
        shares = convertToShares(_assets);
    }

    /// TODO: should we also expose public function without auth?
    /// @dev request asset deposit for a receiver to be included in the next epoch execution. Asset is locked in the escrow on request submission.
    /// @return 
    function requestDeposit(uint256 _assets, address _receiver) auth public {
        require(hasMember(msg.sender), "Tranche4626/not-a-member");

        require(
            ERC20Like(asset).transferFrom(_receiver, address(escrow), _assets),
            "Centrifuge/Tranche4626/currency-transfer-failed"
        );
        gateway.increaseInvestOrder(poolId, trancheId, _receiver, address(asset), _assets);
    }

    /// TODO: should we also expose public function without auth?
    /// @dev collect the shares after pool epoch execution. 
    function deposit(uint256 _assets, address _receiver)  auth public returns (uint256 shares) {
        _mint(shares_ = previewDeposit(assets_), assets_, _receiver, msg.sender);
        emit Deposit(caller_, receiver_, assets_, shares_);

        
    }

    /// @dev 
    /// @return
    function maxMint(address receiver) external view returns (uint256 maxShares);
    /// @dev 
    /// @return
    function previewMint(uint256 shares) external view returns (uint256 assets);
    /// @dev 
    /// @return
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    /// @dev 
    /// @return
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);
    /// @dev 
    /// @return
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    /// @dev 
    /// @return
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    /// @dev 
    /// @return
    function maxRedeem(address owner) external view returns (uint256 maxShares);
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
