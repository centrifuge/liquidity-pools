// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Root} from "src/Root.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {RestrictionManager} from "src/token/RestrictionManager.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Escrow} from "src/Escrow.sol";
import {Tranche} from "src/token/Tranche.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {CentrifugeRouter} from "src/CentrifugeRouter.sol";
import {AxelarAdapter} from "src/gateway/adapters/axelar/Adapter.sol";
import {GasService} from "src/gateway/GasService.sol";
import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {TrancheFactory} from "src/factories/TrancheFactory.sol";
import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {TransferProxyFactory} from "src/factories/TransferProxyFactory.sol";
import {Guardian} from "src/admin/Guardian.sol";
import {Deployment, Configuration} from "script/Deployer.sol";
import {DeploymentManager} from "test/utils/DeploymentManager.sol";
import "forge-std/Test.sol";

interface ISafe {
    function getOwners() external view returns (address[] memory);
    function isOwner(address signer) external view returns (bool);
    function getThreshold() external view returns (uint256);
}

interface IAxelarContract {
    function contractId() external view returns (bytes32);
}

contract ForkTest is Test {
    using stdJson for string;

    Deployment[] deployments;

    function setUp() public virtual {
        // Mainnet
        _loadDeployment("mainnet", "ethereum-mainnet");
        _loadDeployment("mainnet", "base-mainnet");
        _loadDeployment("mainnet", "arbitrum-mainnet");
        _loadDeployment("mainnet", "celo-mainnet");

        // Testnet
        // _loadDeployment("testnet", "ethereum-sepolia-demo");
        _loadDeployment("testnet", "base-sepolia-demo");
    }

    function testContractSetup() public {
        if (vm.envOr("FORK_TESTS", false)) {
            for (uint256 i; i < deployments.length; i++) {
                // Read deployment file
                Deployment memory deployment = deployments[i];
                _loadFork(i);

                _verifyRoot(deployment);
                _verifyGuardian(deployment);
                _verifyRestrictionManager(deployment);
                _verifyInvestmentManager(deployment);
                _verifyPoolmanager(deployment);
                _verifyRouter(deployment);
                _verifyGateway(deployment);
                _verifyGasService(deployment);
                _verifyEscrow(deployment);
                _verifyRouterEscrow(deployment);
                _verifyAxelarAdapter(deployment);
                _verifyTrancheFactory(deployment);
                _verifyVaultFactory(deployment);
                _verifyTransferProxyFactory(deployment);
            }
        }
    }

    function _verifyRoot(Deployment memory deployment) internal {
        address root = deployment.root;
        address escrow = deployment.escrow;
        address gateway = deployment.gateway;
        address guardian = deployment.guardian;
        address router = deployment.router;
        address deployer = deployment.deployer;

        Root _root = Root(root);

        assertEq(_root.escrow(), escrow);

        assertEq(_root.delay(), deployment.configuration.delay);
        assertEq(_root.paused(), false);

        assertEq(_root.wards(gateway), 1);
        assertEq(_root.wards(guardian), 1);
        assertEq(_root.wards(deployer), 0);

        assertTrue(_root.endorsed(router));
        assertTrue(_root.endorsed(escrow));
    }

    function _verifyGuardian(Deployment memory deployment) internal {
        address guardian = deployment.guardian;
        address gateway = deployment.gateway;
        address root = deployment.root;
        address safe = deployment.adminSafe;

        Guardian _guardian = Guardian(guardian);

        assertEq(address(_guardian.gateway()), gateway);
        assertEq(address(_guardian.root()), root);
        assertEq(address(_guardian.safe()), safe);
    }

    function _verifyRestrictionManager(Deployment memory deployment) internal {
        address manager = deployment.restrictionManager;
        address root = deployment.root;
        address poolManager = deployment.poolManager;
        address deployer = deployment.deployer;

        RestrictionManager _restrictionManager = RestrictionManager(manager);

        assertEq(address(_restrictionManager.root()), root);

        assertEq(_restrictionManager.wards(root), 1);
        assertEq(_restrictionManager.wards(poolManager), 1);
        assertEq(_restrictionManager.wards(deployer), 0);
    }

    function _verifyInvestmentManager(Deployment memory deployment) internal {
        address manager = deployment.investmentManager;
        address root = deployment.root;
        address escrow = deployment.escrow;
        address gateway = deployment.gateway;
        address poolManager = deployment.poolManager;
        address vaultFactory = deployment.vaultFactory;
        address deployer = deployment.deployer;

        InvestmentManager _investmentManager = InvestmentManager(manager);

        assertEq(address(_investmentManager.root()), root);
        assertEq(address(_investmentManager.escrow()), escrow);
        assertEq(address(_investmentManager.gateway()), gateway);
        assertEq(address(_investmentManager.poolManager()), poolManager);

        assertEq(_investmentManager.wards(root), 1);
        assertEq(_investmentManager.wards(gateway), 1);
        assertEq(_investmentManager.wards(vaultFactory), 1);
        assertEq(_investmentManager.wards(deployer), 0);
    }

    function _verifyPoolmanager(Deployment memory deployment) internal {
        address manager = deployment.poolManager;
        address escrow = deployment.escrow;
        address gateway = deployment.gateway;
        address investmentManager = deployment.investmentManager;
        address trancheFactory = deployment.trancheFactory;
        address vaultFactory = deployment.vaultFactory;
        address gasService = deployment.gasService;
        address root = deployment.root;
        address deployer = deployment.deployer;

        PoolManager _poolManager = PoolManager(manager);

        assertEq(address(_poolManager.escrow()), escrow);
        assertEq(address(_poolManager.gateway()), gateway);
        assertEq(address(_poolManager.investmentManager()), investmentManager);
        assertEq(address(_poolManager.trancheFactory()), trancheFactory);
        assertEq(address(_poolManager.vaultFactory()), vaultFactory);
        assertEq(address(_poolManager.gasService()), gasService);

        assertEq(_poolManager.wards(root), 1);
        assertEq(_poolManager.wards(gateway), 1);
        assertEq(_poolManager.wards(deployer), 0);
    }

    function _verifyRouter(Deployment memory deployment) internal {
        address router = deployment.router;
        address escrow = deployment.routerEscrow;
        address gateway = deployment.gateway;
        address root = deployment.root;
        address deployer = deployment.deployer;
        address poolManager = deployment.poolManager;

        CentrifugeRouter _router = CentrifugeRouter(router);

        assertEq(address(_router.gateway()), gateway);
        assertEq(address(_router.escrow()), escrow);
        assertEq(address(_router.poolManager()), poolManager);

        assertEq(_router.wards(root), 1);
        assertEq(_router.wards(deployer), 0);
    }

    function _verifyGateway(Deployment memory deployment) internal {
        address payable gateway = payable(deployment.gateway);
        address root = deployment.root;
        address poolManager = deployment.poolManager;
        address investmentManager = deployment.investmentManager;
        address router = deployment.router;
        address gasService = deployment.gasService;
        address[] memory adapters = deployment.adapters;
        address guardian = deployment.guardian;
        address deployer = deployment.deployer;

        Gateway _gateway = Gateway(gateway);

        assertEq(address(_gateway.root()), root);
        assertEq(address(_gateway.poolManager()), poolManager);
        assertEq(address(_gateway.investmentManager()), investmentManager);
        assertEq(address(_gateway.gasService()), gasService);

        assertTrue(_gateway.payers(router));
        for (uint256 i; i < adapters.length; i++) {
            assertEq(_gateway.adapters(i), adapters[i]);
        }
        assertEq(_gateway.quorum(), 1);
        assertEq(_gateway.activeSessionId(), 0);

        assertEq(_gateway.wards(root), 1);
        assertEq(_gateway.wards(guardian), 1);
        assertEq(_gateway.wards(deployer), 0);
    }

    function _verifyGasService(Deployment memory deployment) internal {
        address gasService = deployment.gasService;
        address root = deployment.root;
        address gateway = deployment.gateway;
        address deployer = deployment.deployer;

        GasService _gasService = GasService(gasService);

        assertEq(_gasService.wards(root), 1);
        assertEq(_gasService.wards(gateway), 1);
        assertEq(_gasService.wards(deployer), 0);
    }

    function _verifyEscrow(Deployment memory deployment) internal {
        address escrow = deployment.escrow;
        address root = deployment.root;
        address poolManager = deployment.poolManager;
        address deployer = deployment.deployer;

        Escrow _escrow = Escrow(escrow);

        assertEq(_escrow.wards(root), 1);
        assertEq(_escrow.wards(poolManager), 1);
        assertEq(_escrow.wards(deployer), 0);
    }

    function _verifyRouterEscrow(Deployment memory deployment) internal {
        address escrow = deployment.routerEscrow;
        address root = deployment.root;
        address router = deployment.router;
        address deployer = deployment.deployer;

        Escrow _routerEscrow = Escrow(escrow);

        assertEq(_routerEscrow.wards(root), 1);
        assertEq(_routerEscrow.wards(router), 1);
        assertEq(_routerEscrow.wards(deployer), 0);
    }

    function _verifyAxelarAdapter(Deployment memory deployment) internal {
        address adapter = deployment.adapters[0];
        address gateway = deployment.gateway;
        address root = deployment.root;
        address deployer = deployment.deployer;
        // TODO Take this from the adapter not from the deployment.
        address axelarGateway = address(0);
        address axelarGasService = address(0);

        AxelarAdapter _adapter = AxelarAdapter(adapter);
        assertEq(address(_adapter.gateway()), gateway);
        assertEq(address(_adapter.axelarGateway()), axelarGateway);
        assertEq(address(_adapter.axelarGasService()), axelarGasService);

        assertEq(_adapter.wards(root), 1);
        assertEq(_adapter.wards(deployer), 0);

        assertEq(IAxelarContract(axelarGateway).contractId(), keccak256("axelar-gateway"));
        assertEq(IAxelarContract(axelarGasService).contractId(), keccak256("axelar-gas-service"));

        if (!deployment.configuration.isTestnet) {
            assertEq(_adapter.CENTRIFUGE_ID(), "centrifuge");
            assertEq(_adapter.CENTRIFUGE_AXELAR_EXECUTABLE(), "0xc1757c6A0563E37048869A342dF0651b9F267e41");
            assertEq(_adapter.centrifugeIdHash(), keccak256(bytes("centrifuge")));
            assertEq(_adapter.centrifugeAddressHash(), keccak256(bytes("0x7369626CEF070000000000000000000000000000")));
        }
    }

    function _verifyTrancheFactory(Deployment memory deployment) internal {
        address trancheFactory = deployment.trancheFactory;
        address root = deployment.root;
        address poolManager = deployment.poolManager;
        address deployer = deployment.deployer;

        TrancheFactory _trancheFactory = TrancheFactory(trancheFactory);

        assertEq(address(_trancheFactory.root()), root);

        assertEq(_trancheFactory.wards(root), 1);
        assertEq(_trancheFactory.wards(poolManager), 1);
        assertEq(_trancheFactory.wards(deployer), 0);
    }

    function _verifyVaultFactory(Deployment memory deployment) internal {
        address vaultFactory = deployment.vaultFactory;
        address root = deployment.root;
        address poolManager = deployment.poolManager;
        address deployer = deployment.deployer;

        ERC7540VaultFactory _vaultFactory = ERC7540VaultFactory(vaultFactory);

        assertEq(address(_vaultFactory.root()), root);
        assertEq(_vaultFactory.wards(root), 1);
        assertEq(_vaultFactory.wards(poolManager), 1);
        assertEq(_vaultFactory.wards(deployer), 0);
    }

    function _verifyTransferProxyFactory(Deployment memory deployment) internal {
        address transferProxyFactory = deployment.transferProxyFactory;
        address root = deployment.root;
        address poolManager = deployment.poolManager;
        address deployer = deployment.deployer;

        TransferProxyFactory _transferProxyFactory = TransferProxyFactory(transferProxyFactory);
        assertEq(address(_transferProxyFactory.root()), root);
        assertEq(address(_transferProxyFactory.poolManager()), poolManager);

        assertEq(_transferProxyFactory.wards(root), 1);
        assertEq(_transferProxyFactory.wards(deployer), 0);
    }

    function testAdminSigners() public {
        if (vm.envOr("FORK_TESTS", false)) {
            for (uint256 i = 0; i < deployments.length; i++) {
                Deployment memory current = deployments[i];
                if (!current.configuration.isTestnet) {
                    // Read deployment file
                    address adminSafe = current.adminSafe;
                    // TODO: Actually get the
                    address[] memory adminSigners = new address[](0);
                    _loadFork(i);

                    // Check Safe signers
                    ISafe safe = ISafe(adminSafe);
                    address[] memory signers = safe.getOwners();
                    assertEq(signers.length, adminSigners.length);
                    for (uint256 j = 0; j < adminSigners.length; j++) {
                        assertTrue(safe.isOwner(adminSigners[j]));
                    }

                    // Check threshold
                    assertEq(safe.getThreshold(), 4);
                }
            }
        }
    }

    // can return deterministci address based on initialization code, deployer and the constructor params.
    function testDeterminism() public {
        if (vm.envOr("FORK_TESTS", false)) {
            for (uint256 i = 0; i < deployments.length; i++) {
                Deployment memory current = deployments[i];
                bool isDeterministicallyDeployed = current.configuration.isDeterministic;
                if (!isDeterministicallyDeployed) continue;

                // Read deployment file
                address root = current.root;
                address escrow = current.escrow;
                address routerEscrow = current.routerEscrow;
                address restrictionManager = current.restrictionManager;
                address trancheFactory = current.trancheFactory;
                address transferProxyFactory = current.transferProxyFactory;
                _loadFork(i);

                if (deployments[i].configuration.isTestnet) {
                    // Check address
                    assertEq(root, 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC);
                    assertEq(escrow, 0x0000000005F458Fd6ba9EEb5f365D83b7dA913dD);
                    assertEq(routerEscrow, 0x0F1b890fC6774Ef9b14e99de16302E24A6e7B4F7);
                    assertEq(restrictionManager, 0x4737C3f62Cc265e786b280153fC666cEA2fBc0c0);
                    assertEq(trancheFactory, 0xFa072fB96F737bdBCEa28c921d43c34d3a4Dbb6C);
                    assertEq(transferProxyFactory, 0xbe55eBC29344a26550E07EF59aeF791fA3b2A817);
                }

                // Check bytecode
                assertEq(keccak256(root.code), 0xe3b8893b70f2552e1919f152cdcf860187d2dd89387f0c9f6b6e3f19f530e741);
                assertEq(keccak256(escrow.code), 0x4cbd7efe2319295d7c29c38569ab8ff94d1dce284d8f678753e3c934427f889d);
                assertEq(
                    keccak256(routerEscrow.code), 0x4cbd7efe2319295d7c29c38569ab8ff94d1dce284d8f678753e3c934427f889d
                );
                assertEq(
                    keccak256(restrictionManager.code),
                    0xd831f92a7a47bd72b65b00b9ad7dc3b417e2da5a7c90551f0480edead15497e1
                );
                assertEq(
                    keccak256(trancheFactory.code), 0xba57bbc9fd815f451d25952918142f10cea1c6d90d2fa0c94e9f856a318cf2a7
                );
                assertEq(
                    keccak256(transferProxyFactory.code),
                    0x625180e41eba3fd52bb06958a14cee7dc2b12123015a95f353fe00ca4425201d
                );
            }
        }
    }

    function _loadDeployment(string memory folder, string memory name) internal {
        deployments.push(DeploymentManager.loadFromJson(folder, name));
    }

    function _loadFork(uint256 id) internal {
        // string memory rpcUrl = abi.decode(deployments[id].parseRaw(".rpcUrl"), (string));
        // uint256 forkId = vm.createFork(rpcUrl);
        // vm.selectFork(forkId);
    }
}
