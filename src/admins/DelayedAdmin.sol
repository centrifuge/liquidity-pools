// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {Root} from "../Root.sol";
import "./../util/Auth.sol";

contract DelayedAdmin is Auth {
    Root public root;

    // --- Events ---
    event File(bytes32 indexed what, address indexed data);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "root") {
            root = Root(data);
        } else {
            revert("DelayedAdmin/file-unrecognized-param");
        }
        emit File(what, data);
    }

    // --- Admin actions ---
    function pause() public auth {
        root.pause();
    }

    function unpause() public auth {
        root.unpause();
    }

    function schedule(address target) public auth {
        root.scheduleRely(target);
    }

    function cancelRely(address target) public auth {
        root.cancelRely(target);
    }
}
