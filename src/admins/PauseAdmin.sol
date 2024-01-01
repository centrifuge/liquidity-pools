// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "../Root.sol";
import {Auth} from "./../Auth.sol";

/// @title  Pause Admin
/// @dev    Any ward can manage accounts who can pause.
///         Any pauser can instantaneously pause the Root.
contract PauseAdmin is Auth {
    Root public immutable root;

    mapping(address => uint256) public pausers;

    event AddPauser(address indexed user);
    event RemovePauser(address indexed user);

    constructor(address root_) {
        root = Root(root_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier canPause() {
        require(pausers[msg.sender] == 1, "PauseAdmin/not-authorized-to-pause");
        _;
    }

    // --- Administration ---
    function addPauser(address user) external auth {
        pausers[user] = 1;
        emit AddPauser(user);
    }

    function removePauser(address user) external auth {
        pausers[user] = 0;
        emit RemovePauser(user);
    }

    // --- Admin actions ---
    function pause() external canPause {
        root.pause();
    }
}
