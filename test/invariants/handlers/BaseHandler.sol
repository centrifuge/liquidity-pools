// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {TestSetup} from "test/TestSetup.t.sol";
import {MockCentrifugeChain} from "test/mock/MockCentrifugeChain.sol";
import {MathLib} from "src/util/MathLib.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import "forge-std/Test.sol";

interface SystemStateLike {
    function numInvestors() external view returns (uint256);
    function investors(uint256 index) external view returns (address);
}

contract BaseHandler is Test {
    SystemStateLike immutable state;

    address currentInvestor;

    constructor(address state_) {
        state = SystemStateLike(state_);
    }

    modifier useRandomInvestor(uint256 investorIndex_) {
        currentInvestor = state.investors(_bound(investorIndex_, 0, state.numInvestors() - 1));
        (, address currentPrank,) = vm.readCallers();
        if (currentPrank != currentInvestor) vm.startPrank(currentInvestor);
        _;
        vm.stopPrank();
    }

    /// @notice Returns the smallest of two numbers.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }
}
