// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import {Root} from "src/Root.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Escrow} from "src/Escrow.sol";
import {TrancheToken} from "src/token/Tranche.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {RestrictionManagerFactory} from "src/factories/RestrictionManagerFactory.sol";
import {TrancheTokenFactory} from "src/factories/TrancheTokenFactory.sol";
import {Guardian, SafeLike} from "src/admin/Guardian.sol";

interface RouterLike {
    function send(bytes memory message) external;
    function wards(address ward) external view returns (uint256);
}

contract ForkTest is Test {
    using stdJson for string;

    string[] deployments;

    function setUp() public virtual {
        // Mainnet
        _loadDeployment("mainnet", "ethereum-mainnet");
        _loadDeployment("mainnet", "base-mainnet");
        _loadDeployment("mainnet", "arbitrum-mainnet");
        _loadDeployment("mainnet", "celo-mainnet");

        // Testnet
        // TODO: sepolia currently fails because the admin is missing on the DelayedAdmin
        // Should be redeployed and then re-enabled here
        // _loadDeployment("testnet", "ethereum-sepolia");
    }

    function testBaseContractsWiredCorrectly() public {
        if (vm.envOr("FORK_TESTS", false)) {
            for (uint256 i = 0; i < deployments.length; i++) {
                // Read deployment file
                address root = _get(i, ".contracts.root");
                address investmentManager = _get(i, ".contracts.investmentManager");
                address poolManager = _get(i, ".contracts.poolManager");
                address gateway = _get(i, ".contracts.gateway");
                address escrow = _get(i, ".contracts.escrow");
                address router = _get(i, ".contracts.router");
                address trancheTokenFactory = _get(i, ".contracts.trancheTokenFactory");
                address vaultFactory = _get(i, ".contracts.vaultFactory");
                address restrictionManagerFactory = _get(i, ".contracts.restrictionManagerFactory");
                address deployer = _get(i, ".config.deployer");
                address adminSafe = _get(i, ".config.adminSafe");
                _loadFork(i);

                // InvestmentManager
                assertEq(address(InvestmentManager(investmentManager).escrow()), escrow);
                assertEq(address(InvestmentManager(investmentManager).gateway()), gateway);
                assertEq(address(InvestmentManager(investmentManager).poolManager()), poolManager);
                assertEq(InvestmentManager(investmentManager).wards(poolManager), 1);
                assertEq(Escrow(escrow).wards(investmentManager), 1);
                assertEq(InvestmentManager(investmentManager).wards(root), 1);
                assertEq(InvestmentManager(investmentManager).wards(deployer), 0);
                assertEq(InvestmentManager(investmentManager).wards(adminSafe), 0);

                // PoolManager
                assertEq(address(PoolManager(poolManager).gateway()), gateway);
                assertEq(address(PoolManager(poolManager).escrow()), escrow);
                assertEq(address(PoolManager(poolManager).investmentManager()), investmentManager);
                assertEq(address(PoolManager(poolManager).trancheTokenFactory()), trancheTokenFactory);
                assertEq(address(PoolManager(poolManager).vaultFactory()), vaultFactory);
                assertEq(address(PoolManager(poolManager).restrictionManagerFactory()), restrictionManagerFactory);
                assertEq(Escrow(escrow).wards(poolManager), 1);
                assertEq(PoolManager(poolManager).wards(root), 1);
                assertEq(PoolManager(poolManager).wards(deployer), 0);
                assertEq(PoolManager(poolManager).wards(adminSafe), 0);

                // Gateway
                assertEq(address(Gateway(gateway).investmentManager()), investmentManager);
                assertEq(address(Gateway(gateway).poolManager()), poolManager);
                assertEq(address(Gateway(gateway).root()), root);
                assertEq(address(InvestmentManager(investmentManager).gateway()), gateway);
                assertEq(address(PoolManager(poolManager).gateway()), gateway);
                // assertEq(address(Gateway(gateway).aggregator()), aggregator);
                assertEq(Gateway(gateway).wards(root), 1);
                assertEq(Root(root).wards(gateway), 1);
                assertEq(Gateway(gateway).wards(deployer), 0);
                assertEq(Gateway(gateway).wards(adminSafe), 0);

                // Escrow
                assertEq(Escrow(escrow).wards(root), 1);
                assertEq(Escrow(escrow).wards(deployer), 0);
                assertEq(Escrow(escrow).wards(adminSafe), 0);

                // UserEscrow

                // Router
                assertEq(RouterLike(router).wards(root), 1);
                assertEq(RouterLike(router).wards(deployer), 0);
                assertEq(RouterLike(router).wards(adminSafe), 0);
            }
        }
    }

    function testFactoriesWiredCorrectly() public {
        if (vm.envOr("FORK_TESTS", false)) {
            for (uint256 i = 0; i < deployments.length; i++) {
                // Read deployment file
                address root = _get(i, ".contracts.root");
                address poolManager = _get(i, ".contracts.poolManager");
                address trancheTokenFactory = _get(i, ".contracts.trancheTokenFactory");
                address vaultFactory = _get(i, ".contracts.vaultFactory");
                address restrictionManagerFactory = _get(i, ".contracts.restrictionManagerFactory");
                address deployer = _get(i, ".config.deployer");
                address adminSafe = _get(i, ".config.adminSafe");
                _loadFork(i);

                // TrancheTokenFactory
                assertEq(TrancheTokenFactory(trancheTokenFactory).wards(root), 1);
                assertEq(TrancheTokenFactory(trancheTokenFactory).wards(deployer), 0);
                assertEq(TrancheTokenFactory(trancheTokenFactory).wards(adminSafe), 0);

                // ERC7540VaultFactory
                assertEq(ERC7540VaultFactory(vaultFactory).root(), root);
                assertEq(ERC7540VaultFactory(vaultFactory).wards(root), 1);
                assertEq(ERC7540VaultFactory(vaultFactory).wards(poolManager), 1);
                assertEq(ERC7540VaultFactory(vaultFactory).wards(deployer), 0);
                assertEq(ERC7540VaultFactory(vaultFactory).wards(adminSafe), 0);

                // RestrictionManagerFactory
                assertEq(RestrictionManagerFactory(restrictionManagerFactory).wards(root), 1);
                assertEq(RestrictionManagerFactory(restrictionManagerFactory).wards(deployer), 0);
                assertEq(RestrictionManagerFactory(restrictionManagerFactory).wards(adminSafe), 0);
            }
        }
    }

    function testAdminsWiredCorrectly() public {
        if (vm.envOr("FORK_TESTS", false)) {
            for (uint256 i = 0; i < deployments.length; i++) {
                // Read deployment file
                address root = _get(i, ".contracts.root");
                address guardian = _get(i, ".contracts.guardian");
                address deployer = _get(i, ".config.deployer");
                address adminSafe = _get(i, ".config.adminSafe");
                _loadFork(i);

                // Root
                assertEq(Root(root).delay(), 48 hours);
                assertEq(Root(root).paused(), false);

                // Guardian
                assertEq(address(Guardian(guardian).root()), root);
                assertEq(address(Guardian(guardian).safe()), adminSafe);
                assertEq(Root(root).wards(guardian), 1);
            }
        }
    }

    function testAdminSigners() public {
        if (vm.envOr("FORK_TESTS", false)) {
            for (uint256 i = 0; i < deployments.length; i++) {
                bool isTestnet = abi.decode(deployments[i].parseRaw(".isTestnet"), (bool));
                if (!isTestnet) {
                    // Read deployment file
                    address adminSafe = _get(i, ".config.adminSafe");
                    address[] memory adminSigners =
                        abi.decode(deployments[i].parseRaw(".config.adminSigners"), (address[]));
                    _loadFork(i);

                    // Check Safe signers
                    SafeLike safe = SafeLike(adminSafe);
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

    function testDeterminism() public {
        if (vm.envOr("FORK_TESTS", false)) {
            for (uint256 i = 0; i < deployments.length; i++) {
                if (i == 0) {
                    i++;
                    // Skipping ethereum-mainnet for now as the tranche token factory needs an update
                    // TODO: remove this after migrating ethereum-mainnet
                    continue;
                }

                bool isTestnet = abi.decode(deployments[i].parseRaw(".isTestnet"), (bool));
                if (!isTestnet) {
                    // Read deployment file
                    address root = _get(i, ".contracts.root");
                    address escrow = _get(i, ".contracts.escrow");
                    address trancheTokenFactory = _get(i, ".contracts.trancheTokenFactory");
                    _loadFork(i);

                    // Check address
                    assertEq(root, 0x498016d30Cd5f0db50d7ACE329C07313a0420502);
                    assertEq(escrow, 0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936);
                    assertEq(trancheTokenFactory, 0x2d60cd1527073419423B14666E2D43C1Cf28B152);

                    // Check bytecode
                    assertEq(keccak256(root.code), 0x47102707d876a808849bf1be9c8af0e58d889c65918ee3af3a95dd54fa389070);
                    assertEq(keccak256(escrow.code), 0xf54c8ad5a295c7d20a91165917fb20fbcd2952c625696710f8f9a012fcc8e042);
                    assertEq(
                        keccak256(trancheTokenFactory.code),
                        0x0f2863a7a7ffa6f3db8a3aab70ded9e170752a36734eca4a0ff19dc52ec5e97b
                    );
                }
            }
        }
    }

    function _loadDeployment(string memory folder, string memory name) internal {
        deployments.push(vm.readFile(string.concat(vm.projectRoot(), "/deployments/", folder, "/", name, ".json")));
    }

    function _loadFork(uint256 id) internal {
        string memory rpcUrl = abi.decode(deployments[id].parseRaw(".rpcUrl"), (string));
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);
    }

    function _get(uint256 id, string memory key) internal view returns (address) {
        return abi.decode(deployments[id].parseRaw(key), (address));
    }
}
