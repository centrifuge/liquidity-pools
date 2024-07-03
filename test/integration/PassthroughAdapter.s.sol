// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Deployer} from "../../script/Deployer.sol";
import {PassthroughAdapter} from "./PassthroughAdapter.sol";

contract PassthroughAdapterScript is Deployer {
    function setUp() public {}

    function run() public {
        deploy(msg.sender);
        PassthroughAdapter adapter = new PassthroughAdapter();
        wire(address(adapter));
        adapter.file("gateway", address(gateway));
    }
}
