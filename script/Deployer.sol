// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "src/Root.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {GasService} from "src/gateway/GasService.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {TrancheTokenFactory} from "src/factories/TrancheTokenFactory.sol";
import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {RestrictionManagerFactory} from "src/factories/RestrictionManagerFactory.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Escrow} from "src/Escrow.sol";
import {CentrifugeRouter} from "src/CentrifugeRouter.sol";
import {Guardian} from "src/admin/Guardian.sol";
import {MockSafe} from "test/mocks/MockSafe.sol";
import "forge-std/Script.sol";

interface AdapterLike {
    function file(bytes32 what, address data) external;
}

interface AuthLike {
    function rely(address who) external;
    function deny(address who) external;
}

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
    CentrifugeRouter public centrifugeRouter; // TODO: rename once adapters => adapters rename is in
    address public vaultFactory;
    address public restrictionManagerFactory;
    address public trancheTokenFactory;

    function deploy(address deployer) public {
        // If no salt is provided, a pseudo-random salt is generated,
        // thus effectively making the deployment non-deterministic
        bytes32 salt = vm.envOr(
            "DEPLOYMENT_SALT", keccak256(abi.encodePacked(string(abi.encodePacked(blockhash(block.number - 1)))))
        );
        escrow = new Escrow{salt: salt}(deployer);
        root = new Root{salt: salt}(address(escrow), delay, deployer);

        vaultFactory = address(new ERC7540VaultFactory(address(root)));
        restrictionManagerFactory = address(new RestrictionManagerFactory(address(root)));
        trancheTokenFactory = address(new TrancheTokenFactory{salt: salt}(address(root), deployer));
        investmentManager = new InvestmentManager(address(root), address(escrow));
        poolManager = new PoolManager(address(escrow), vaultFactory, restrictionManagerFactory, trancheTokenFactory);

        // TODO THESE VALUES NEEDS TO BE CHECKED
        gasService = new GasService(20000000000000000, 20000000000000000, 2500000000000000000, 178947400000000);
        gasService.rely(address(root));

        gateway = new Gateway(address(root), address(investmentManager), address(poolManager), address(gasService));
        routerEscrow = new Escrow(deployer);
        centrifugeRouter = new CentrifugeRouter(address(routerEscrow), address(poolManager), address(gateway));
        AuthLike(address(routerEscrow)).rely(address(centrifugeRouter));
        root.endorse(address(centrifugeRouter));
        root.endorse(address(escrow));

        AuthLike(vaultFactory).rely(address(poolManager));
        AuthLike(trancheTokenFactory).rely(address(poolManager));
        AuthLike(restrictionManagerFactory).rely(address(poolManager));

        AuthLike(vaultFactory).rely(address(root));
        AuthLike(trancheTokenFactory).rely(address(root));
        AuthLike(restrictionManagerFactory).rely(address(root));

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

        centrifugeRouter.rely(address(root));
        investmentManager.file("gateway", address(gateway));
        poolManager.file("gateway", address(gateway));
        investmentManager.rely(address(root));
        investmentManager.rely(address(gateway));
        investmentManager.rely(address(vaultFactory));
        poolManager.rely(address(root));
        poolManager.rely(address(gateway));
        gateway.rely(address(root));
        AuthLike(adapter).rely(address(root));
        AuthLike(address(escrow)).rely(address(root));
        AuthLike(address(routerEscrow)).rely(address(root));
        AuthLike(address(escrow)).rely(address(poolManager));
    }

    function removeDeployerAccess(address adapter, address deployer) public {
        AuthLike(adapter).deny(deployer);
        AuthLike(vaultFactory).deny(deployer);
        AuthLike(trancheTokenFactory).deny(deployer);
        AuthLike(restrictionManagerFactory).deny(deployer);
        root.deny(deployer);
        investmentManager.deny(deployer);
        poolManager.deny(deployer);
        escrow.deny(deployer);
        routerEscrow.deny(deployer);
        gateway.deny(deployer);
        centrifugeRouter.deny(deployer);
        gasService.deny(deployer);
    }
}
