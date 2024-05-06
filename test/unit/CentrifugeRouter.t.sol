// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import {SucceedingRequestReceiver} from "test/mocks/SucceedingRequestReceiver.sol";
import {FailingRequestReceiver} from "test/mocks/FailingRequestReceiver.sol";

contract CentriufgeRoutertest is BaseTest {}
