// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import "./ERC20.sol";

interface MemberlistLike {
    function hasMember(address) external view returns (bool);
    function member(address) external;
}

interface ERC20Like {
    function mint(address user, uint256 value) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function balanceOf(address user) external view returns (uint256 value);
    function burn(address user, uint256 value) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function totalSupply() external returns (uint256);
    function approve(address _spender, uint256 _value) external returns (bool);
}

interface RestrictedTokenLike is ERC20Like {
    function memberlist() external view returns (address);
    function hasMember(address user) external view returns (bool);
    function file(bytes32 contractName, address addr) external;
}

contract RestrictedToken is ERC20 {
    MemberlistLike public memberlist;

    uint128 public latestPrice; // tokenPrice
    uint256 public lastPriceUpdate; // timestamp of the latest share price update

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
        else revert("file-unrecognized-param");
        emit File(what, data);
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

    // auth functions
    function updateTokenPrice(uint128 _tokenPrice) public auth {
        latestPrice = _tokenPrice;
        lastPriceUpdate = block.timestamp;
    }
}
