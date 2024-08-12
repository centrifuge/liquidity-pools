// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import {ERC20} from "src/token/ERC20.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test_router_enableLockDepositRequest_0() public {
  
   deployNewTokenPoolAndTranche(89, 18004218757120792111658028824198997115297255063200251133818735496719698405081);
  
   poolManager_disallowAsset();
  
   router_enableLockDepositRequest(962463753670198263845198479275736274117931165824443693898157238524284680);
}
}
