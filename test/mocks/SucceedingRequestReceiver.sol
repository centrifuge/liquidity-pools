// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/mocks/Mock.sol";
import {IERC7540DepositReceiver, IERC7540RedeemReceiver} from "src/interfaces/IERC7540.sol";

contract SucceedingRequestReceiver is IERC7540DepositReceiver, IERC7540RedeemReceiver, Mock {
    function onERC7540DepositReceived(
        address _operator,
        address _owner,
        uint256 _requestId,
        uint256 _assets,
        bytes memory _data
    ) external returns (bytes4) {
        values_address["requestDeposit_operator"] = _operator;
        values_address["requestDeposit_owner"] = _owner;
        values_uint256["requestDeposit_requestId"] = _requestId;
        values_uint256["requestDeposit_assets"] = _assets;
        values_bytes["requestDeposit_data"] = _data;

        return bytes4(keccak256("onERC7540DepositReceived(address,address,uint256,uint256,bytes)"));
    }

    function onERC7540RedeemReceived(
        address _operator,
        address _owner,
        uint256 _requestId,
        uint256 _shares,
        bytes memory _data
    ) external returns (bytes4) {
        values_address["requestRedeem_operator"] = _operator;
        values_address["requestRedeem_owner"] = _owner;
        values_uint256["requestRedeem_requestId"] = _requestId;
        values_uint256["requestRedeem_shares"] = _shares;
        values_bytes["requestRedeem_data"] = _data;

        return bytes4(keccak256("onERC7540RedeemReceived(address,address,uint256,uint256,bytes)"));
    }
}
