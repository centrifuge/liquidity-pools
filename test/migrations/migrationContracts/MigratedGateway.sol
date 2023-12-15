// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "src/gateway/Gateway.sol";

contract MigratedGateway is Gateway {
    constructor(address _root, address _investmentManager, address poolManager_, address router_)
        Gateway(_root, _investmentManager, poolManager_, router_)
    {
        // TODO: migrate routers
    }
}
