// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import "./util/Auth.sol";
import "./token/ERC20Like.sol";
import "./util/Math.sol";

interface ERC20PermitLike {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    // erc2612 functions
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface TrancheTokenLike is ERC20Like, ERC20PermitLike {
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
    function previewDeposit(address user, address liquidityPool, uint256 assets) external view returns (uint256);
    function previewMint(address user, address liquidityPool, uint256 shares) external view returns (uint256);
    function previewWithdraw(address user, address liquidityPool, uint256 assets) external view returns (uint256);
    function previewRedeem(address user, address liquidityPool, uint256 shares) external view returns (uint256);
    function requestRedeem(uint256 shares, address receiver) external;
    function requestDeposit(uint256 assets, address receiver) external;
    function collectInvest(uint64 poolId, bytes16 trancheId, address receiver, address currency) external;
    function collectRedeem(uint64 poolId, bytes16 trancheId, address receiver, address currency) external;
    function PRICE_DECIMALS() external view returns (uint8);
}

/// @title LiquidityPool
/// @author ilinzweilin
/// @dev Liquidity Pool implementation for Centrifuge Pools following the EIP4626 standard.
///
/// @notice Each Liquidity Pool is a tokenized vault issuing shares as restricted ERC20 tokens against currency deposits based on the current share price.
/// This is extending the EIP4626 standard by 'requestRedeem' & 'requestDeposit' functions, where redeem and deposit orders are submitted to the pools
/// to be included in the execution of the following epoch. After execution users can use the redeem and withdraw functions to get their shares and/or assets from the pools.
contract LiquidityPool is Auth, ERC20Like {
    using Math for uint256;

    InvestmentManagerLike public investmentManager;

    uint64 public immutable poolId;
    bytes16 public immutable trancheId;

    /// @notice asset: The underlying stable currency of the Liquidity Pool. Note: 1 Centrifuge Pool can have multiple Liquidity Pools for the same Tranche token with different underlying currencies (assets).
    address public immutable asset;

    /// @notice share: The restricted ERC-20 Liquidity pool token. Has a ratio (token price) of underlying assets exchanged on deposit/withdraw/redeem. Liquidity pool tokens on evm represent tranche tokens on centrifuge chain (even though in the current implementation one tranche token on centrifuge chain can be split across multiple liquidity pool tokens on EVM).
    TrancheTokenLike public immutable share;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event DepositRequested(address indexed owner, uint256 assets);
    event RedeemRequested(address indexed owner, uint256 shares);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    constructor(uint64 poolId_, bytes16 trancheId_, address asset_, address share_, address investmentManager_) {
        poolId = poolId_;
        trancheId = trancheId_;
        asset = asset_;
        share = TrancheTokenLike(share_);
        investmentManager = InvestmentManagerLike(investmentManager_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev function either called by a ward or message.sender has approval to spent sender´s tokens
    modifier withTokenApproval(address sender, uint256 amount) {
        require(
            wards[msg.sender] == 1 || msg.sender == sender || share.allowance(sender, msg.sender) >= amount,
            "LiquidityPool/no-token-allowance"
        );
        _;
    }

    /// @dev function either called by a ward or message.sender has approval to spent sender´s currency
    modifier withCurrencyApproval(address sender, uint256 amount) {
        require(
            wards[msg.sender] == 1 || msg.sender == sender || ERC20Like(asset).allowance(sender, msg.sender) >= amount,
            "LiquidityPool/no-currency-allowance"
        );
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) public auth {
        if (what == "investmentManager") investmentManager = InvestmentManagerLike(data);
        else revert("LiquidityPool/file-unrecognized-param");
        emit File(what, data);
    }

    // --- ERC4626 functions ---
    /// @dev The total amount of vault shares
    /// @return Total amount of the underlying vault assets including accrued interest
    function totalAssets() public view returns (uint256) {
        return totalSupply().mulDiv(latestPrice(), 10 ** investmentManager.PRICE_DECIMALS(), Math.Rounding.Down);
    }

    /// @dev Calculates the amount of shares / tranche tokens that any user would get for the amount of assets provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = assets.mulDiv(
            10 ** (investmentManager.PRICE_DECIMALS() + share.decimals() - ERC20Like(asset).decimals()),
            latestPrice(),
            Math.Rounding.Down
        );
    }

    /// @dev Calculates the asset value for an amount of shares / tranche tokens provided. The calcultion is based on the token price from the most recent epoch retrieved from Centrifuge chain.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = shares.mulDiv(
            latestPrice(),
            10 ** (investmentManager.PRICE_DECIMALS() + share.decimals() - ERC20Like(asset).decimals()),
            Math.Rounding.Down
        );
    }

    /// @return Maximum amount of stable currency that can be deposited into the Tranche by the receiver after the epoch had been executed on Centrifuge chain.
    function maxDeposit(address receiver) public view returns (uint256) {
        return investmentManager.maxDeposit(receiver, address(this));
    }

    /// @return shares that any user would get for an amount of assets provided -> convertToShares
    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        shares = investmentManager.previewDeposit(msg.sender, address(this), assets);
    }

    /// @dev request asset deposit for a receiver to be included in the next epoch execution. Asset is locked in the escrow on request submission
    function requestDeposit(uint256 assets, address owner) public withCurrencyApproval(owner, assets) {
        investmentManager.requestDeposit(assets, owner);
        emit DepositRequested(owner, assets);
    }

    function requestDepositWithPermit(uint256 assets, address owner, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        ERC20PermitLike(asset).permit(owner, address(investmentManager), assets, deadline, v, r, s);
        investmentManager.requestDeposit(assets, owner);
        emit DepositRequested(owner, assets);
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
        assets = investmentManager.previewMint(msg.sender, address(this), shares);
    }

    /// @dev request share redemption for a receiver to be included in the next epoch execution. Shares are locked in the escrow on request submission
    function requestRedeem(uint256 shares, address owner) public withTokenApproval(owner, shares) {
        investmentManager.requestRedeem(shares, owner);
        emit RedeemRequested(owner, shares);
    }

    function requestRedeemWithPermit(uint256 shares, address owner, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        share.permit(owner, address(investmentManager), shares, deadline, v, r, s);
        investmentManager.requestRedeem(shares, owner);
        emit RedeemRequested(owner, shares);
    }

    /// @return maxAssets that the receiver can withdraw
    function maxWithdraw(address receiver) public view returns (uint256 maxAssets) {
        return investmentManager.maxWithdraw(receiver, address(this));
    }

    /// @return shares that a user would need to redeem in order to receive the given amount of assets -> convertToAssets
    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        shares = investmentManager.previewWithdraw(msg.sender, address(this), assets);
    }

    /// @dev Withdraw assets after successful epoch execution. Receiver will receive an exact amount of assets for a certain amount of shares that has been redeemed from Owner during epoch execution.
    /// @return shares that have been redeemed for the excat assets amount
    function withdraw(uint256 assets, address receiver, address owner)
        public
        withCurrencyApproval(owner, assets)
        returns (uint256 shares)
    {
        // check if messgae sender can spend owners funds
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
        assets = investmentManager.previewRedeem(msg.sender, address(this), shares);
    }

    /// @dev Redeem shares after successful epoch execution. Receiver will receive assets for the exact amount of redeemed shares from Owner after epoch execution.
    /// @return assets currency payout for the exact amount of redeemed shares
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        uint256 currencyPayout = investmentManager.processRedeem(shares, receiver, owner);
        // make sure msg.sender has the allowance to delegate owner's funds
        require(
            wards[msg.sender] == 1 || msg.sender == owner
                || ERC20Like(asset).allowance(owner, msg.sender) >= currencyPayout,
            "LiquidityPool/no-currency-allowance"
        );
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

    // --- Restrictions ---
    function latestPrice() public view returns (uint256) {
        return share.latestPrice();
    }

    function hasMember(address user) public returns (bool) {
        return share.hasMember(user);
    }

    // --- Helpers ---
    /// @dev In case of unsuccessful tx, parse the revert message
    function _successCheck(bool success) internal pure {
        if (success == false) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }
}
