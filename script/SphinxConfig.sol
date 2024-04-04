// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Sphinx, Network} from "@sphinx-labs/contracts/SphinxPlugin.sol";

contract SphinxConfig is Sphinx {
    function setUp() public virtual {
        sphinxConfig.owners = [address(0x423420Ae467df6e90291fd0252c0A8a637C1e03f)];
        sphinxConfig.orgId = "clsypbcrw0001zqwy1arndx1t";
        sphinxConfig.testnets = [Network.sepolia, Network.polygon_mumbai];
        sphinxConfig.projectName = "Liquidity_Pools";
        sphinxConfig.threshold = 1;
    }
}
