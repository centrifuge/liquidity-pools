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
import {IAuth} from "src/interfaces/IAuth.sol";
import "forge-std/Script.sol";

struct Configuration {
    uint256 delay;
    bool isTestnet;
    bool isDeterministic;
}

struct Deployment {
    address escrow;
    address routerEscrow;
    address root;
    address router;
    address vaultFactory;
    address trancheFactory;
    address transferProxyFactory;
    address poolManager;
    address investmentManager;
    address restrictionManager;
    address gasService;
    address payable gateway;
    address guardian;
    address deployer;
    address adminSafe;
    address[] adapters;
    Configuration configuration;
}

contract Deployer is Script {
    uint256 internal constant delay = 48 hours;

    Escrow public escrow;
    Escrow public routerEscrow;
    Root public root;
    CentrifugeRouter public router;
    ERC7540VaultFactory public vaultFactory;
    TrancheFactory public trancheFactory;
    TransferProxyFactory public transferProxyFactory;
    PoolManager public poolManager;
    InvestmentManager public investmentManager;
    RestrictionManager public restrictionManager;
    GasService public gasService;
    Gateway public gateway;
    Guardian public guardian;
    address deployer;
    address adminSafe;
    address[] adapters;

    Deployment deployment;

    function deploy(address _deployer, address _adminSafe, address[] memory _adapters_)
        public
        returns (Deployment memory)
    {
        require(_adminSafe != address(0), "Deployer/AdminSafe-must-be-set");
        require(_adapters_.length > 0, "Deployer/At-least-one-router-is-needed");
        console.log("Deployer is: ", _deployer);
        console.log("Sender is: ", msg.sender);
        console.log("This address is: ", address(this));
        // If no salt is provided, a pseudo-random salt is generated,
        // thus effectively making the deployment non-deterministic
        bytes32 salt = vm.envOr(
            "DEPLOYMENT_SALT", keccak256(abi.encodePacked(string(abi.encodePacked(blockhash(block.number - 1)))))
        );

        uint64 messageCost = uint64(vm.envOr("MESSAGE_COST", uint256(20000000000000000))); // in Weight
        uint64 proofCost = uint64(vm.envOr("PROOF_COST", uint256(20000000000000000))); // in Weigth
        uint128 gasPrice = uint128(vm.envOr("GAS_PRICE", uint256(2500000000000000000))); // Centrifuge Chain
        uint256 tokenPrice = vm.envOr("TOKEN_PRICE", uint256(178947400000000)); // CFG/ETH

        escrow = new Escrow{salt: salt}(_deployer);
        routerEscrow = new Escrow{salt: keccak256(abi.encodePacked(salt, "escrow2"))}(_deployer);
        root = new Root{salt: salt}(address(escrow), delay, _deployer);

        vaultFactory = new ERC7540VaultFactory(address(root));
        trancheFactory = new TrancheFactory{salt: salt}(address(root), _deployer);
        transferProxyFactory = new TransferProxyFactory{salt: salt}(address(root), _deployer);

        poolManager = new PoolManager(address(escrow), address(vaultFactory), address(trancheFactory));
        investmentManager = new InvestmentManager(address(root), address(escrow));
        restrictionManager = new RestrictionManager{salt: salt}(address(root), _deployer);

        gasService = new GasService(messageCost, proofCost, gasPrice, tokenPrice);
        gateway = new Gateway(address(root), address(poolManager), address(investmentManager), address(gasService));
        router = new CentrifugeRouter(address(routerEscrow), address(gateway), address(poolManager));
        guardian = new Guardian(_adminSafe, address(root), address(gateway));

        deployer = _deployer;
        adminSafe = _adminSafe;
        adapters = _adapters_;

        _endorse();
        _rely();
        _file();
        _storeDeployment();

        return deployment;
    }

    function _endorse() internal {
        root.endorse(address(router));
        root.endorse(address(escrow));
    }

    function _rely() internal {
        // Rely on PoolManager
        escrow.rely(address(poolManager));
        vaultFactory.rely(address(poolManager));
        trancheFactory.rely(address(poolManager));
        restrictionManager.rely(address(poolManager));

        // Rely on Root
        router.rely(address(root));
        poolManager.rely(address(root));
        investmentManager.rely(address(root));
        gateway.rely(address(root));
        gasService.rely(address(root));
        escrow.rely(address(root));
        routerEscrow.rely(address(root));
        transferProxyFactory.rely(address(root));
        vaultFactory.rely(address(root));
        trancheFactory.rely(address(root));
        restrictionManager.rely(address(root));
        address[] memory adapters_ = adapters;
        for (uint256 i; i < adapters_.length; i++) {
            IAuth(adapters_[i]).rely(address(root));
        }

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

    function _file() internal {
        poolManager.file("investmentManager", address(investmentManager));
        poolManager.file("gasService", address(gasService));
        poolManager.file("gateway", address(gateway));

        investmentManager.file("poolManager", address(poolManager));
        investmentManager.file("gateway", address(gateway));

        gateway.file("adapters", adapters);
        gateway.file("payers", address(router), true);

        transferProxyFactory.file("poolManager", address(poolManager));
    }

    function _storeDeployment() internal {
        deployment.escrow = address(escrow);
        deployment.routerEscrow = address(routerEscrow);
        deployment.root = address(root);
        deployment.vaultFactory = address(vaultFactory);
        deployment.trancheFactory = address(trancheFactory);
        deployment.transferProxyFactory = address(transferProxyFactory);
        deployment.poolManager = address(poolManager);
        deployment.investmentManager = address(investmentManager);
        deployment.restrictionManager = address(restrictionManager);
        deployment.gasService = address(gasService);
        deployment.gateway = payable(address(gateway));
        deployment.router = address(router);
        deployment.guardian = address(guardian);
        deployment.deployer = address(deployer);
        deployment.adminSafe = address(adminSafe);

        deployment.configuration = Configuration({
            delay: delay,
            isTestnet: vm.envBool("IS_TESTNET"),
            isDeterministic: vm.envBool("IS_DETERMINISTIC")
        });
    }

    function removeDeployerAccess() public {
        address _deployer = deployer;

        vaultFactory.deny(_deployer);
        trancheFactory.deny(_deployer);
        restrictionManager.deny(_deployer);
        transferProxyFactory.deny(_deployer);
        root.deny(_deployer);
        investmentManager.deny(_deployer);
        poolManager.deny(_deployer);
        escrow.deny(_deployer);
        routerEscrow.deny(_deployer);
        gateway.deny(_deployer);
        router.deny(_deployer);
        gasService.deny(_deployer);

        address[] memory _adapters = adapters;
        uint256 adaptersCount = _adapters.length;
        for (uint256 i; i < adaptersCount; i++) {
            IAuth(_adapters[i]).deny(deployer);
        }
    }
}
