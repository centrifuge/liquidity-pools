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
import {InterestDistributor} from "src/operators/InterestDistributor.sol";
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
    TransferProxyFactory public transferProxyFactory;
    InterestDistributor public interestDistributor;
    address public vaultFactory;
    address public restrictionManager;
    address public trancheFactory;

    function deploy(address deployer) public {
        // If no salt is provided, a pseudo-random salt is generated,
        // thus effectively making the deployment non-deterministic
        bytes32 salt = vm.envOr(
            "DEPLOYMENT_SALT", keccak256(abi.encodePacked(string(abi.encodePacked(blockhash(block.number - 1)))))
        );

        uint64 messageCost = uint64(vm.envOr("MESSAGE_COST", uint256(20000000000000000))); // in Weight
        uint64 proofCost = uint64(vm.envOr("PROOF_COST", uint256(20000000000000000))); // in Weigth
        uint128 gasPrice = uint128(vm.envOr("GAS_PRICE", uint256(2500000000000000000))); // Centrifuge Chain
        uint256 tokenPrice = vm.envOr("TOKEN_PRICE", uint256(178947400000000)); // CFG/ETH

        escrow = new Escrow{salt: salt}(deployer);
        routerEscrow = new Escrow{salt: keccak256(abi.encodePacked(salt, "escrow2"))}(deployer);
        root = new Root{salt: salt}(address(escrow), delay, deployer);
        vaultFactory = address(new ERC7540VaultFactory(address(root)));
        restrictionManager = address(new RestrictionManager{salt: salt}(address(root), deployer));
        trancheFactory = address(new TrancheFactory{salt: salt}(address(root), deployer));
        investmentManager = new InvestmentManager(address(root), address(escrow));
        poolManager = new PoolManager(address(escrow), vaultFactory, trancheFactory);
        transferProxyFactory = new TransferProxyFactory{salt: salt}(address(root), deployer);
        gasService = new GasService(messageCost, proofCost, gasPrice, tokenPrice);
        gateway = new Gateway(address(root), address(poolManager), address(investmentManager), address(gasService));
        router = new CentrifugeRouter(address(routerEscrow), address(gateway), address(poolManager));
        guardian = new Guardian(adminSafe, address(root), address(gateway));
        // TODO: poolManager is not deployed deterministically!
        interestDistributor = new InterestDistributor{salt: salt}(address(poolManager));

        _endorse();
        _rely();
        _file();
    }

    function _endorse() internal {
        root.endorse(address(router));
        root.endorse(address(escrow));
    }

    function _rely() internal {
        // Rely on PoolManager
        escrow.rely(address(poolManager));
        IAuth(vaultFactory).rely(address(poolManager));
        IAuth(trancheFactory).rely(address(poolManager));
        IAuth(restrictionManager).rely(address(poolManager));

        // Rely on Root
        router.rely(address(root));
        poolManager.rely(address(root));
        investmentManager.rely(address(root));
        gateway.rely(address(root));
        gasService.rely(address(root));
        escrow.rely(address(root));
        routerEscrow.rely(address(root));
        transferProxyFactory.rely(address(root));
        IAuth(vaultFactory).rely(address(root));
        IAuth(trancheFactory).rely(address(root));
        IAuth(restrictionManager).rely(address(root));

        // Rely on guardian
        root.rely(address(guardian));
        gateway.rely(address(guardian));

        // Rely on gateway
        root.rely(address(gateway));
        investmentManager.rely(address(gateway));
        poolManager.rely(address(gateway));
        gasService.rely(address(gateway));

        // Rely on others
        routerEscrow.rely(address(router));
        investmentManager.rely(address(vaultFactory));
    }

    function _file() public {
        poolManager.file("investmentManager", address(investmentManager));
        poolManager.file("gasService", address(gasService));
        poolManager.file("gateway", address(gateway));

        investmentManager.file("poolManager", address(poolManager));
        investmentManager.file("gateway", address(gateway));

        gateway.file("payers", address(router), true);

        transferProxyFactory.file("poolManager", address(poolManager));
    }

    function wire(address adapter) public {
        adapters.push(adapter);
        gateway.file("adapters", adapters);
        IAuth(adapter).rely(address(root));
    }

    function removeDeployerAccess(address adapter, address deployer) public {
        IAuth(adapter).deny(deployer);
        IAuth(vaultFactory).deny(deployer);
        IAuth(trancheFactory).deny(deployer);
        IAuth(restrictionManager).deny(deployer);
        transferProxyFactory.deny(deployer);
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
