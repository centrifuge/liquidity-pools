// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/Test.sol";
// import {Router} from "@nomad-xyz/contracts-router/contracts/Router.sol";

contract ConnectorRouter is Test {
    uint32 immutable CENTRIFUGE_CHAIN_DOMAIN = 3000;

    function updateInvestOrder(
        uint256 poolId,
        uint256[] calldata trancheId,
        uint256 amount
    ) external {
        console.log(poolId);
        console.log(amount);
        // TODO: send message to Nomad Home contract
        return;
    }

    // function send(bytes memory message) internal {
    //     (_home()).dispatch(
    //         CENTRIFUGE_CHAIN_DOMAIN,
    //         _mustHaveRemote(CENTRIFUGE_CHAIN_DOMAIN),
    //         message
    //     );
    // }
}
