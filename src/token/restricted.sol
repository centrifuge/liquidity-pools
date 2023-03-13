// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.6;

import "./erc20.sol";

interface MemberlistLike {
    function hasMember(address) external view returns (bool);
    function member(address) external;
}

interface ERC20Like {
    function mint(address usr, uint256 wad) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function balanceOf(address usr) external view returns (uint256 wad);
    function burn(address usr, uint256 wad) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function totalSupply() external returns (uint256);
    function approve(address _spender, uint256 _value) external returns (bool);
}

interface RestrictedTokenLike is ERC20Like {
    function memberlist() external view returns (address);
    function hasMember(address usr) external view returns (bool);
    function file(bytes32 contractName, address addr) external;
}

// Only mebmber with a valid (not expired) membership should be allowed to receive tokens
contract RestrictedToken is ERC20 {
    MemberlistLike public memberlist;

    event File(bytes32 indexed what, address data);

    modifier checkMember(address usr) {
        memberlist.member(usr);
        _;
    }

    function hasMember(address usr) public view returns (bool) {
        return memberlist.hasMember(usr);
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_, decimals_) {}

    function file(bytes32 what, address data) external auth {
        if (what == "memberlist") memberlist = MemberlistLike(data);
        else revert("file-unrecognized-param");
        emit File(what, data);
    }

    function transferFrom(address from, address to, uint256 value) public override checkMember(to) returns (bool) {
        return super.transferFrom(from, to, value);
    }
}
