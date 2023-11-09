// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "src/Root.sol";
import {AxelarRouter} from "src/gateway/routers/axelar/Router.sol";
import {Gateway, InvestmentManagerLike} from "src/gateway/Gateway.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Escrow} from "src/Escrow.sol";
import {UserEscrow} from "src/UserEscrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {LiquidityPoolFactory, RestrictionManagerFactory, TrancheTokenFactory} from "src/util/Factory.sol";
import "forge-std/Script.sol";

interface RouterLike {
    function file(bytes32 what, address data) external;
    function rely(address who) external;
    function deny(address who) external;
}

contract Deployer is Script {
    uint256 internal constant delay = 48 hours;

    address admin;

    Root public root;
    InvestmentManager public investmentManager;
    PoolManager public poolManager;
    Escrow public escrow;
    UserEscrow public userEscrow;
    PauseAdmin public pauseAdmin;
    DelayedAdmin public delayedAdmin;
    Gateway public gateway;
    address public liquidityPoolFactory;
    address public restrictionManagerFactory;
    address public trancheTokenFactory;

    function deployInvestmentManager(address deployer) public {
        // If no salt is provided, a pseudo-random salt is generated,
        // thus effectively making the deployment non-deterministic
        bytes32 salt = vm.envOr(
            "DEPLOYMENT_SALT", keccak256(abi.encodePacked(string(abi.encodePacked(blockhash(block.number - 1)))))
        );
        escrow = new Escrow{salt: salt}(deployer);
        userEscrow = new UserEscrow();
        root = new Root{salt: salt}(address(escrow), delay, deployer);

        address liquidityPoolFactory = address(new LiquidityPoolFactory(address(root)));
        address restrictionManagerFactory = address(new RestrictionManagerFactory(address(root)));
        address trancheTokenFactory = address(new TrancheTokenFactory{salt: salt}(address(root), deployer));
        investmentManager = new InvestmentManager(address(escrow), address(userEscrow));
        poolManager =
            new PoolManager(address(escrow), liquidityPoolFactory, restrictionManagerFactory, trancheTokenFactory);

        LiquidityPoolFactory(liquidityPoolFactory).rely(address(poolManager));
        TrancheTokenFactory(trancheTokenFactory).rely(address(poolManager));
        RestrictionManagerFactory(restrictionManagerFactory).rely(address(poolManager));

        LiquidityPoolFactory(liquidityPoolFactory).rely(address(root));
        TrancheTokenFactory(trancheTokenFactory).rely(address(root));
        RestrictionManagerFactory(restrictionManagerFactory).rely(address(root));
    }

    function wire(address router) public {
        // Deploy gateway and admins
        pauseAdmin = new PauseAdmin(address(root));
        delayedAdmin = new DelayedAdmin(address(root), address(pauseAdmin));
        gateway = new Gateway(address(root), address(investmentManager), address(poolManager), address(router));
        pauseAdmin.rely(address(delayedAdmin));
        root.rely(address(pauseAdmin));
        root.rely(address(delayedAdmin));
        root.rely(address(gateway));

        // Wire gateway
        investmentManager.file("poolManager", address(poolManager));
        poolManager.file("investmentManager", address(investmentManager));
        investmentManager.file("gateway", address(gateway));
        poolManager.file("gateway", address(gateway));
        investmentManager.rely(address(root));
        investmentManager.rely(address(poolManager));
        poolManager.rely(address(root));
        gateway.rely(address(root));
        RouterLike(router).rely(address(root));
        Escrow(address(escrow)).rely(address(root));
        Escrow(address(escrow)).rely(address(investmentManager));
        UserEscrow(address(userEscrow)).rely(address(root));
        UserEscrow(address(userEscrow)).rely(address(investmentManager));
        Escrow(address(escrow)).rely(address(poolManager));
    }

    function giveAdminAccess() public {
        pauseAdmin.rely(address(admin));
        delayedAdmin.rely(address(admin));
    }

    function removeDeployerAccess(address router, address deployer) public {
        RouterLike(router).deny(deployer);
        root.deny(deployer);
        investmentManager.deny(deployer);
        poolManager.deny(deployer);
        escrow.deny(deployer);
        gateway.deny(deployer);
        pauseAdmin.deny(deployer);
        delayedAdmin.deny(deployer);
    }
}
