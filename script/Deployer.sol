// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Root} from "src/Root.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {GasService} from "src/gateway/GasService.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {TrancheFactory} from "src/factories/TrancheFactory.sol";
import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {RestrictionManager} from "src/token/RestrictionManager.sol";
import {TransferProxyFactory} from "src/factories/TransferProxyFactory.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Escrow} from "src/Escrow.sol";
import {CentrifugeRouter} from "src/CentrifugeRouter.sol";
import {Guardian} from "src/admin/Guardian.sol";
import {MockSafe} from "test/mocks/MockSafe.sol";
import {IAuth} from "src/interfaces/IAuth.sol";
import "forge-std/Script.sol";

contract Deployer is Script {
    uint256 internal constant delay = 48 hours;
    address adminSafe;
    address[] adapters;

    Root public root;
    InvestmentManager public investmentManager;
    PoolManager public poolManager;
    Escrow public escrow;
    Escrow public routerEscrow;
    Guardian public guardian;
    Gateway public gateway;
    GasService public gasService;
    CentrifugeRouter public router;
    address public vaultFactory;
    address public restrictionManager;
    address public trancheFactory;
    address public transferProxyFactory;

    function deploy(address deployer) public {
        // If no salt is provided, a pseudo-random salt is generated,
        // thus effectively making the deployment non-deterministic
        bytes32 salt = vm.envOr(
            "DEPLOYMENT_SALT", keccak256(abi.encodePacked(string(abi.encodePacked(blockhash(block.number - 1)))))
        );
        escrow = new Escrow{salt: salt}(deployer);
        root = new Root{salt: salt}(address(escrow), delay, deployer);

        vaultFactory = address(new ERC7540VaultFactory(address(root)));
        restrictionManager = address(new RestrictionManager{salt: salt}(address(root)));
        trancheFactory = address(new TrancheFactory{salt: salt}(address(root), deployer));
        investmentManager = new InvestmentManager(address(root), address(escrow));
        poolManager = new PoolManager(address(escrow), vaultFactory, trancheFactory);
        transferProxyFactory = address(new TransferProxyFactory{salt: salt}(address(poolManager)));

        // TODO THESE VALUES NEEDS TO BE CHECKED
        gasService = new GasService(20000000000000000, 20000000000000000, 2500000000000000000, 178947400000000);
        gasService.rely(address(root));

        gateway = new Gateway(address(root), address(poolManager), address(investmentManager), address(gasService));
        routerEscrow = new Escrow(deployer);
        router = new CentrifugeRouter(address(routerEscrow), address(gateway), address(poolManager));
        IAuth(address(routerEscrow)).rely(address(router));
        root.endorse(address(router));
        root.endorse(address(escrow));

        IAuth(vaultFactory).rely(address(poolManager));
        IAuth(trancheFactory).rely(address(poolManager));
        IAuth(restrictionManager).rely(address(poolManager));

        IAuth(vaultFactory).rely(address(root));
        IAuth(trancheFactory).rely(address(root));
        IAuth(restrictionManager).rely(address(root));

        guardian = new Guardian(adminSafe, address(root), address(gateway));
    }

    function wire(address adapter) public {
        adapters.push(adapter);

        // Wire guardian
        root.rely(address(guardian));
        gateway.rely(address(guardian));

        // Wire gateway
        gateway.file("adapters", adapters);
        root.rely(address(gateway));
        investmentManager.file("poolManager", address(poolManager));
        poolManager.file("investmentManager", address(investmentManager));
        poolManager.file("gasService", address(gasService));

        router.rely(address(root));
        investmentManager.file("gateway", address(gateway));
        poolManager.file("gateway", address(gateway));
        investmentManager.rely(address(root));
        investmentManager.rely(address(gateway));
        investmentManager.rely(address(vaultFactory));
        poolManager.rely(address(root));
        poolManager.rely(address(gateway));
        gateway.rely(address(root));
        IAuth(adapter).rely(address(root));
        IAuth(address(escrow)).rely(address(root));
        IAuth(address(routerEscrow)).rely(address(root));
        IAuth(address(escrow)).rely(address(poolManager));
    }

    function removeDeployerAccess(address adapter, address deployer) public {
        IAuth(adapter).deny(deployer);
        IAuth(vaultFactory).deny(deployer);
        IAuth(trancheFactory).deny(deployer);
        IAuth(restrictionManager).deny(deployer);
        root.deny(deployer);
        investmentManager.deny(deployer);
        poolManager.deny(deployer);
        escrow.deny(deployer);
        routerEscrow.deny(deployer);
        gateway.deny(deployer);
        router.deny(deployer);
        gasService.deny(deployer);
    }
}
