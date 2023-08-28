// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {Root} from "../Root.sol";
import "./../util/Auth.sol";

contract PauseAdmin is Auth {
    Root public root;

    mapping(address => uint256) public pausers;

    event AddPauser(address indexed user);
    event RemovePauser(address indexed user);

    // --- Events ---
    event File(bytes32 indexed what, address indexed data);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier canPause() {
        require(pausers[msg.sender] == 1, "PauseAdmin/not-authorized-to-pause");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "root") {
            root = Root(data);
        } else {
            revert("PauseAdmin/file-unrecognized-param");
        }
        emit File(what, data);
    }

    function addPauser(address user) external auth {
        pausers[user] = 1;
        emit AddPauser(user);
    }

    function removePauser(address user) external auth {
        pausers[user] = 0;
        emit RemovePauser(user);
    }

    // --- Admin actions ---
    function pause() public canPause {
        root.pause();
    }
}
