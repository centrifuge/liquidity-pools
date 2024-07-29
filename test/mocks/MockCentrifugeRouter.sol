// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "./Mock.sol";

contract MockCentrifugeRouter is Mock {
    function requestDeposit(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable
    {
        values_address["requestDeposit_vault"] = vault;
        values_uint256["requestDeposit_amount"] = amount;
        values_address["requestDeposit_controller"] = controller;
        values_address["requestDeposit_owner"] = owner;
        values_uint256["requestDeposit_topUpAmount"] = topUpAmount;
    }

    function requestRedeem(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable
    {
        values_address["requestRedeem_vault"] = vault;
        values_uint256["requestRedeem_amount"] = amount;
        values_address["requestRedeem_controller"] = controller;
        values_address["requestRedeem_owner"] = owner;
        values_uint256["requestRedeem_topUpAmount"] = topUpAmount;
    }

    // Added to be ignored in coverage report
    function test() public {}
}
