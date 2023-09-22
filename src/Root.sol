// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

/// @title  Root
/// @notice Core contract that is a ward on all other deployed contracts.
/// @dev    Pausing can happen instantaneously, but relying on other contracts
///         is restricted to the timelock set by the delay.
contract Root is Auth {
    /// @dev To prevent filing a delay that would block any updates indefinitely
    uint256 internal constant MAX_DELAY = 4 weeks;

    address public immutable escrow;

    mapping(address relyTarget => uint256 timestamp) public schedule;
    uint256 public delay;
    bool public paused;

    // --- Events ---
    event File(bytes32 indexed what, uint256 data);
    event Pause();
    event Unpause();
    event ScheduleRely(address indexed target, uint256 indexed scheduledTime);
    event CancelRely(address indexed target);
    event RelyContract(address indexed target, address indexed user);
    event DenyContract(address indexed target, address indexed user);

    constructor(address _escrow, uint256 _delay, address deployer) {
        require(_delay <= MAX_DELAY, "Root/delay-too-long");

        escrow = _escrow;
        delay = _delay;

        wards[deployer] = 1;
        emit Rely(deployer);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "delay") {
            require(data <= MAX_DELAY, "Root/delay-too-long");
            delay = data;
        } else {
            revert("Root/file-unrecognized-param");
        }
        emit File(what, data);
    }

    // --- Pause management ---
    /// @notice Pause any contracts that depend on `Root.paused()`
    function pause() external auth {
        paused = true;
        emit Pause();
    }

    /// @notice Unpause any contracts that depend on `Root.paused()`
    function unpause() external auth {
        paused = false;
        emit Unpause();
    }

    /// --- Timelocked ward management ---
    /// @notice Schedule relying a new ward after the delay has passed
    function scheduleRely(address target) external auth {
        schedule[target] = block.timestamp + delay;
        emit ScheduleRely(target, schedule[target]);
    }

    /// @notice Cancel a pending scheduled rely
    function cancelRely(address target) external auth {
        schedule[target] = 0;
        emit CancelRely(target);
    }

    /// @notice Execute a scheduled rely
    /// @dev    Can be triggered by anyone since the scheduling is protected
    function executeScheduledRely(address target) public {
        require(schedule[target] != 0, "Root/target-not-scheduled");
        require(schedule[target] <= block.timestamp, "Root/target-not-ready");

        wards[target] = 1;
        emit Rely(target);

        schedule[target] = 0;
    }

    /// --- External contract ward management ---
    /// @notice Make an address a ward on any contract that Root is a ward on
    function relyContract(address target, address user) public auth {
        AuthLike(target).rely(user);
        emit RelyContract(target, user);
    }

    /// @notice Removes an address as a ward on any contract that Root is a ward on
    function denyContract(address target, address user) public auth {
        AuthLike(target).deny(user);
        emit DenyContract(target, user);
    }
}
