// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {ConnectorGateway} from "./routers/Gateway.sol";

contract ConnectorPauseAdmin {
    ConnectorGateway public gateway;

    mapping(address => uint256) public wards;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address indexed data);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "ConnectorAdmin/not-authorized");
        _;
    }

    // --- Auth ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "gateway") {
            gateway = ConnectorGateway(data);
        } else {
            revert("ConnectorAdmin/file-unrecognized-param");
        }
        emit File(what, data);
    }

    // --- Admin ---

    function pause() public auth {
        gateway.pause();
    }

    function unpause() public auth {
        gateway.unpause();
    }

    function cancelSchedule(address spell) public auth {
        gateway.cancelSchedule(spell);
    }
}
