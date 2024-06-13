// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Wrapper} from "src/interfaces/IERC20.sol";
import "forge-std/Test.sol";

contract SimpleERC20Wrapper is IERC20Wrapper {
    constructor()
}
