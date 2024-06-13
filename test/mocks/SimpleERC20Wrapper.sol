// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Wrapper, IERC20Metadata} from "src/interfaces/IERC20.sol";
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract SimpleERC20Wrapper is ERC20, IERC20Wrapper {
    address public underlying;

    constructor(address underlying_) ERC20(IERC20Metadata(underlying_).decimals()) {
        underlying = underlying_;
    }

    function depositFor(address account, uint256 value) external returns (bool) {
        require(
            IERC20Metadata(underlying).transferFrom(msg.sender, address(this), value),
            "SimpleERC20Wrapper/failed-transfer"
        );

        // Obviously unsafe, just for testing purposes
        balanceOf[account] = balanceOf[account] + value;
        totalSupply = totalSupply + value;
        emit Transfer(address(0), account, value);

        return true;
    }

    function withdrawTo(address account, uint256 value) external returns (bool) {
        balanceOf[msg.sender] = balanceOf[msg.sender] - value;
        totalSupply = totalSupply - value;

        IERC20Metadata(underlying).transfer(account, value);
        return true;
    }
}
