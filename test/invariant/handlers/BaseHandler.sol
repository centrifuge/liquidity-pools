// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {MockCentrifugeChain} from "test/mocks/MockCentrifugeChain.sol";
import {MathLib} from "src/libraries/MathLib.sol";

import "forge-std/Test.sol";

interface SystemStateLike {
    function numInvestors() external view returns (uint256);
    function investors(uint256 index) external view returns (address);
    function getShadowVar(address entity, string memory key) external view returns (uint256);
    function setShadowVar(address entity, string memory key, uint256 value) external;
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

    // --- Shadow variables ---
    function getVar(address entity, string memory key) internal view returns (uint256) {
        return state.getShadowVar(entity, key);
    }

    function setVar(address entity, string memory key, uint256 value) internal {
        return state.setShadowVar(entity, key, value);
    }

    function increaseVar(address entity, string memory key, uint256 addition) internal {
        return state.setShadowVar(entity, key, state.getShadowVar(entity, key) + addition);
    }

    function decreaseVar(address entity, string memory key, uint256 addition) internal {
        return state.setShadowVar(entity, key, state.getShadowVar(entity, key) - addition);
    }

    function setMaxVar(address entity, string memory key, uint256 value) internal {
        return state.setShadowVar(entity, key, _max(state.getShadowVar(entity, key), value));
    }

    function setMinVar(address entity, string memory key, uint256 value) internal {
        return state.setShadowVar(entity, key, _min(state.getShadowVar(entity, key), value));
    }

    // --- Helpers ---
    /// @notice Returns the smallest of two numbers.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    /// @notice Returns the largest of two numbers.
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
