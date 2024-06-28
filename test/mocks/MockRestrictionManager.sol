// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/mocks/Mock.sol";
import "src/token/RestrictionManager.sol";

contract MockRestrictionManager is RestrictionManager, Mock {
    constructor(address root_) RestrictionManager(root_) {}

    function onERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        public
        override
        returns (bytes4)
    {
        uint8 restrictionCode = detectTransferRestriction(from, to, value, hookData);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));

        values_address["onERC20Transfer_from"] = from;
        values_address["onERC20Transfer_to"] = to;
        values_uint256["onERC20Transfer_value"] = value;

        return bytes4(keccak256("onERC20Transfer(address,address,uint256,HookData)"));
    }
}
