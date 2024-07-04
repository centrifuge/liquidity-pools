// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Wrapper, IERC20Metadata} from "src/interfaces/IERC20.sol";
import "forge-std/Test.sol";

contract MockERC20Wrapper is ERC20, IERC20Wrapper {
    address public underlying;
    bool shouldDepositFail;
    bool shouldWithdrawFail;

    constructor(address underlying_) ERC20(IERC20Metadata(underlying_).decimals()) {
        underlying = underlying_;
    }

    function depositFor(address account, uint256 value) external returns (bool) {
        if (shouldDepositFail) return false;
        require(
            IERC20Metadata(underlying).transferFrom(msg.sender, address(this), value),
            "MockERC20Wrapper/failed-transfer"
        );

        // Obviously unsafe, just for testing purposes
        balances[account] += value;
        totalSupply = totalSupply + value;
        emit Transfer(address(0), account, value);

        return true;
    }

    function withdrawTo(address account, uint256 value) external returns (bool) {
        if (shouldWithdrawFail) return false;
        balances[msg.sender] -= value;
        totalSupply = totalSupply - value;

        IERC20Metadata(underlying).transfer(account, value);
        return true;
    }

    function shouldFail(bytes32 action, bool value) external {
        if (action == "deposit") shouldDepositFail = value;
        else if (action == "withdraw") shouldWithdrawFail = value;
        else revert("Nothing to fail but yourself!");
    }
}
