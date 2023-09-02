// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";

interface LiquidityPoolLike {
    function approve(address spender, uint256 value) external returns (bool);
    function requestRedeem(uint256 shares, address owner) external;
    function requestDeposit(uint256 assets, address owner) external;
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

interface ERC20Like {
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract Investor is Test {
    constructor() {}

    function approve(address erc20, address spender, uint256 amount) public {
        ERC20Like(erc20).approve(spender, amount);
    }

    function requestRedeem(address lPool, uint256 shares, address owner) public {
        LiquidityPoolLike(lPool).requestRedeem(shares, owner);
    }

    function requestDeposit(address lPool, uint256 assets, address owner) public {
        LiquidityPoolLike(lPool).requestDeposit(assets, owner);
    }

    function deposit(address lPool, uint256 assets, address receiver) public {
        LiquidityPoolLike(lPool).deposit(assets, receiver);
    }

    function mint(address lPool, uint256 shares, address receiver) public {
        LiquidityPoolLike(lPool).mint(shares, receiver);
    }

    function withdraw(address lPool, uint256 assets, address receiver, address owner) public {
        LiquidityPoolLike(lPool).withdraw(assets, receiver, owner);
    }

    function redeem(address lPool, uint256 shares, address receiver, address owner) public {
        LiquidityPoolLike(lPool).withdraw(shares, receiver, owner);
    }

    function transferFrom(address erc20, address sender, address recipient, uint256 amount) public returns (bool) {
        ERC20Like(erc20).transferFrom(sender, recipient, amount);
    }

    function transfer(address erc20, address recipient, uint256 amount) public returns (bool) {
        ERC20Like(erc20).transfer(recipient, amount);
    }

    // Added to be ignored in coverage report
    function test() public {}
}
