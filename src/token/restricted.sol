// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.6;

import "./erc20.sol";

interface MemberlistLike {
    function hasMember(address) external view returns (bool);
    function member(address) external;
}

interface ERC20Like {
    function mint(address usr, uint wad) external;
}

interface RestrictedTokenLike is ERC20Like {
    function memberlist() external view returns (address);
    function hasMember(address usr) external view returns (bool);
}

// Only mebmber with a valid (not expired) membership should be allowed to receive tokens
contract RestrictedToken is ERC20 {

    MemberlistLike public memberlist; 
    modifier checkMember(address usr) { memberlist.member(usr); _; }
    
    function hasMember(address usr) public view returns (bool) {
        return memberlist.hasMember(usr);
    }

    constructor(string memory symbol_, string memory name_) ERC20(symbol_, name_) {}

    function depend(bytes32 contractName, address addr) public auth {
        if (contractName == "memberlist") { memberlist = MemberlistLike(addr); }
        else revert();
    }

    function transferFrom(address from, address to, uint wad) checkMember(to) public override returns (bool) {
        return super.transferFrom(from, to, wad);
    }
}
