// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Wrapper, IERC20Metadata} from "src/interfaces/IERC20.sol";
import "forge-std/Test.sol";

contract SimpleERC20Wrapper is IERC20Wrapper {
    IERC20Metadata public underlying;

    constructor(address underlying_) ERC20(IERC20Metadata(underlying_).decimals()) {
        underlying = IERC20Metadata(underlying_);
    }

    function depositFor(address account, uint256 value) external returns (bool);
        require(underlying.transferFrom(msg.sender, address(this), value), "SimpleERC20Wrapper/failed-transfer");
        mint(account, value);
        return true;
    }

    function withdrawTo(address account, uint256 value) external returns (bool);
        burn(msg.sender, value);
        underlying.transfer(account, value);
        return true;
    }
}