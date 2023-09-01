// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./ERC20Like.sol";

interface MemberlistLike {
    function hasMember(address) external view returns (bool);
    function member(address) external;
}

interface TrancheTokenLike is ERC20Like {
    function hasMember(address user) external view returns (bool);
    function updatePrice(uint128 price) external;
    function memberlist() external returns (address);
    function file(bytes32 what, string memory data) external;
}

contract TrancheToken is ERC20 {
    MemberlistLike public memberlist;

    uint128 public latestPrice; // tranche token price
    uint256 public lastPriceUpdate; // timestamp of the price update

    mapping(address => bool) public liquidityPools;

    // --- Events ---
    event File(bytes32 indexed what, address data);

    constructor(uint8 decimals_) ERC20(decimals_) {}

    modifier checkMember(address user) {
        memberlist.member(user);
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external virtual auth {
        if (what == "memberlist") memberlist = MemberlistLike(data);
        else revert("TrancheToken/file-unrecognized-param");
        emit File(what, data);
    }

    function addLiquidityPool(address liquidityPool) public auth {
        liquidityPools[liquidityPool] = true;
    }

    function removeLiquidityPool(address liquidityPool) public auth {
        liquidityPools[liquidityPool] = false;
    }

    // --- Restrictions ---
    function hasMember(address user) public view returns (bool) {
        return memberlist.hasMember(user);
    }

    function transfer(address to, uint256 value) public override checkMember(to) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override checkMember(to) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function mint(address to, uint256 value) public override checkMember(to) {
        return super.mint(to, value);
    }

    // --- Manage liquidity pools ---
    function isTrustedForwarder(address forwarder) public view override returns (bool) {
        // Liquiditiy Pools are considered trusted forwarders
        // for the ERC2771Context implementation of the underlying
        // ERC20 token
        return liquidityPools[forwarder];
    }

    // --- Pricing ---
    function setPrice(uint128 price, uint256 priceAge) public auth {
        require(lastPriceUpdate == 0, "TrancheToken/price-already-set");
        latestPrice = price;
        lastPriceUpdate = priceAge;
    }

    function updatePrice(uint128 price) public auth {
        latestPrice = price;
        lastPriceUpdate = block.timestamp;
    }
}
