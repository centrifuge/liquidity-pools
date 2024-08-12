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
        deployNewTokenPoolAndTranche(213, 1109922828198508092022258837037897407096367457572502626);
        poolManager_updateMember(104682477517645628);

        router_enableLockDepositRequest(1571671511039135344726490349044916145036336035487780128226482691235730529);
        assertTrue(invariant_RE_1());
        poolManager_updateTranchePrice(56901525302466059, 7840914769514120);
        router_executeLockedDepositRequest();
        assertTrue(invariant_RE_1());
    }

    // forge test --match-test test_erc7540_6_deposit_call_target_1 -vv
    function test_erc7540_6_deposit_call_target_1() public {
        deployNewTokenPoolAndTranche(233, 28269320542146199253579888502169902638602973317426694748705922998786179475);
        poolManager_updateMember(104682477517645628);
        poolManager_updateTranchePrice(56901525302466059, 7840914769514120);
        vault_requestDeposit(31538029450636696910582306038649448464549600365089094367785921647207723207717);
        investmentManager_fulfillDepositRequest(
            237784553952399504434353056688092462338, 11272134262104, 8548248478501905158605391940158212738
        );
        poolManager_freeze();
        erc7540_6_deposit_call_target(72);
    }
}
