// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

interface LiquidityPoolLike {
    function requestDeposit(uint256 assets, address receiver, address owner, bytes memory data) external;
    function requestRedeem(uint256 shares, address receiver, address owner, bytes memory data) external;
    function maxDeposit(address owner) external view returns (uint256 maxAssets);
    function maxRedeem(address owner) external view returns (uint256 maxShares);
    function deposit(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function asset() external returns (address asset);
    function share() external returns (address asset);
}

interface ERC20Like {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract LiquidityPoolRouter is Auth {
    mapping(address => mapping(address => uint256)) public lockedRequests;

    // --- Interactions ---

    // --- Deposit ---
    function requestDeposit(address liquidityPool, uint256 amount) external {
        ERC20Like(LiquidityPoolLike(liquidityPool).asset()).transferFrom(msg.sender, address(this), amount);
        LiquidityPoolLike(liquidityPool).requestDeposit(amount, msg.sender, address(this), "");
    }

    function lockDepositRequest(address liquidityPool, uint256 amount) external {
        ERC20Like(LiquidityPoolLike(liquidityPool).asset()).transferFrom(msg.sender, address(this), amount);
        lockedRequests[msg.sender][liquidityPool] += amount;
    }

    function unlockDepositRequest(address liquidityPool) external {
        uint256 lockedRequest = lockedRequests[msg.sender][liquidityPool];
        require(lockedRequest > 0, "LiquidityPoolRouter/investor-has-no-locked-balance");
        lockedRequests[msg.sender][liquidityPool] = 0;
        ERC20Like(LiquidityPoolLike(liquidityPool).asset()).transferFrom(msg.sender, address(this), lockedRequest);
    }

    function executeLockedRequestDeposit(address liquidityPool, address investor) external {
        uint256 lockedRequest = lockedRequests[investor][liquidityPool];
        require(lockedRequest > 0, "LiquidityPoolRouter/investor-has-no-balance");
        lockedRequests[investor][liquidityPool] = 0;
        LiquidityPoolLike(liquidityPool).requestDeposit(lockedRequest, msg.sender, address(this), "");
    }

    function claimDeposit(address liquidityPool, address investor) external {
        uint256 maxDeposit = LiquidityPoolLike(liquidityPool).maxDeposit(investor);
        require(maxDeposit > 0, "LiquidityPoolRouter/investor-has-no-balance-to-claim");
        LiquidityPoolLike(liquidityPool).deposit(maxDeposit, investor, investor);
    }

    // --- Redeem ---
    function requestRedeem(address liquidityPool, uint256 amount) external {
        ERC20Like(LiquidityPoolLike(liquidityPool).share()).transferFrom(msg.sender, address(this), amount);
        LiquidityPoolLike(liquidityPool).requestRedeem(amount, msg.sender, address(this), "");
    }

    function claimRedeem(address liquidityPool, address investor) external {
        uint256 maxRedeem = LiquidityPoolLike(liquidityPool).maxRedeem(investor);
        require(maxRedeem > 0, "LiquidityPoolRouter/investor-has-no-balance-to-claim");
        LiquidityPoolLike(liquidityPool).redeem(maxRedeem, investor, investor);
    }

    // --- ERC20 Recovery ---
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }
}
