// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {AxelarEVMRouter} from "src/routers/axelar/EVMRouter.sol";
import {Gateway, InvestmentManagerLike} from "src/Gateway.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Escrow} from "src/Escrow.sol";
import {PauseAdmin} from "src/admin/PauseAdmin.sol";
import {DelayedAdmin} from "src/admin/DelayedAdmin.sol";
import {LiquidityPoolFactory, MemberlistFactory} from "src/liquidityPool/Factory.sol";
import "forge-std/Script.sol";

interface RouterLike {
    function file(bytes32 what, address data) external;
    function rely(address who) external;
    function deny(address who) external;
}

contract Deployer {
    uint256 shortWait = 24 hours;
    uint256 longWait = 48 hours;
    uint256 gracePeriod = 48 hours;

    address admin;

    InvestmentManager investmentManager;
    Escrow escrow;
    PauseAdmin pauseAdmin;
    DelayedAdmin delayedAdmin;
    Gateway gateway;

    constructor(address admin_) {
        admin = admin_;
    }

    function deployInvestmentManager() public returns (address) {
        address liquidityPoolFactory = address(new LiquidityPoolFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        escrow = new Escrow();
        investmentManager = new InvestmentManager(address(escrow), liquidityPoolFactory, memberlistFactory_);

        return address(investmentManager);
    }

    function wire(address router) public {
        // Deploy gateway and admins
        pauseAdmin = new PauseAdmin();
        delayedAdmin = new DelayedAdmin();
        gateway = new Gateway(address(investmentManager), address(router), shortWait, longWait, gracePeriod);

        // Wire gateway
        investmentManager.file("gateway", address(gateway));
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        RouterLike(router).file("gateway", address(gateway));
        investmentManager.rely(address(gateway));
        RouterLike(router).rely(address(gateway));
        Escrow(address(escrow)).rely(address(gateway));
        Escrow(address(escrow)).rely(address(investmentManager));
    }

    function giveAdminAccess() public {
        pauseAdmin.rely(address(admin));
        delayedAdmin.rely(address(admin));
    }

    function removeDeployerAccess(address router) public {
        RouterLike(router).deny(address(this));
        escrow.deny(address(this));
        gateway.deny(address(this));
        pauseAdmin.deny(address(this));
        delayedAdmin.deny(address(this));
    }
}
