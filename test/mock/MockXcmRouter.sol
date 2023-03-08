// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import "forge-std/Test.sol";
import {ConnectorXCMRouter} from "src/routers/xcm/Router.sol";

contract MockXcmRouter is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    ConnectorXCMRouter public immutable router;

    enum Types {AddPool}

    constructor(address connector) {
        router = new ConnectorXCMRouter(connector, address(this), 108, 99);
    }

    function handle(bytes memory _message) external {
        router.handle(_message);
    }

    function send(bytes memory message) public {
        // do nothing
    }
}
