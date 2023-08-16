// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {Gateway} from "../Gateway.sol";
import "./../auth/auth.sol";

contract DelayedAdmin is Auth {
    Gateway public gateway;

    // --- Events ---
    event File(bytes32 indexed what, address indexed data);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "gateway") {
            gateway = Gateway(data);
        } else {
            revert("Admin/file-unrecognized-param");
        }
        emit File(what, data);
    }

    // --- Admin ---

    function schedule(address spell) public auth {
        gateway.scheduleLongRely(spell);
    }

    function cancelSchedule(address spell) public auth {
        gateway.cancelSchedule(spell);
    }
}
