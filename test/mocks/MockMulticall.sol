// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

struct Call {
    address target;
    bytes callData;
}

contract MockMulticall {
    function aggregate(Call[] calldata calls) public payable returns (uint256 blockNumber, bytes[] memory returnData) {
        blockNumber = block.number;
        uint256 length = calls.length;
        returnData = new bytes[](length);
        Call calldata call;
        for (uint256 i = 0; i < length;) {
            bool success;
            call = calls[i];
            (success, returnData[i]) = call.target.call(call.callData);
            require(success, "Multicall3: call failed");
            unchecked {
                ++i;
            }
        }
    }

    function test() public pure returns (uint256) {
        return 42;
    }
}
