pragma solidity ^0.8.0;

import {LiquidityPool} from "src/LiquidityPool.sol";

contract RedemptionProxy {
    LiquidityPool vault;

    constructor(LiquidityPool _vault) {
        vault = _vault;
    }

    function redeemOnBehalf(uint256 shares, address receiver, address owner) public returns (uint256 tokensWithdrawn) {
        tokensWithdrawn = vault.redeem(shares, receiver, owner );
    }

    function withdrawOnBehalf(uint256 tokens, address receiver, address owner) public returns (uint256 sharesRedeemed) {
        sharesRedeemed = vault.withdraw(tokens, receiver, owner );
    }
}