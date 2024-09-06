// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Deployment, Configuration} from "script/Deployer.sol";
import {JsonParser} from "test/utils/JsonParser.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Vm} from "forge-std/Vm.sol";
import "forge-std/console.sol";

/// @dev    Libraries cannot implement interfaces or extend contract
///         To give access to vm cheat codes we need an instance of Vm.
contract VmInstance is CommonBase {
    function getVm() public pure returns (Vm) {
        return vm;
    }
}

interface ISafe {
    function getOwners() external returns (address[] memory);
}

library DeploymentManager {
    using JsonParser for string;

    function saveAsJson(Deployment memory deployment_, string memory adapterName) internal {
        Vm vm = new VmInstance().getVm();
        string memory root_ = "root";
        vm.serializeUint(root_, "chainId", vm.envUint("CHAIN_ID"));
        vm.serializeString(root_, "rpcUrl", vm.envString("RPC_URL"));

        string memory config_ = "config";
        vm.serializeString(config_, "commitHash", vm.envString("COMMIT_HASH"));
        vm.serializeAddress(config_, "deployer", deployment_.deployer);
        vm.serializeAddress(config_, "admin", deployment_.adminSafe);

        address[] memory signers;

        if (deployment_.adminSafe.code.length > 0) {
            try ISafe(deployment_.adminSafe).getOwners() returns (address[] memory signers_) {
                signers = signers_;
            } catch {
                console.log("Not a Gnosis Safe Wallet!");
            }
        }

        vm.serializeAddress(config_, "adminSigners", signers);
        vm.serializeString(config_, "etherscanUrl", vm.envString("ETHERSCAN_URL"));
        vm.serializeString(config_, "deploymentSalt", vm.envString("DEPLOYMENT_SALT"));
        vm.serializeBool(config_, "isTestnet", deployment_.configuration.isTestnet);
        vm.serializeBool(config_, "isDeterministicallyDeployed", deployment_.configuration.isDeterministic);
        vm.serializeUint(config_, "delay", deployment_.configuration.delay);
        string memory adapter_ = "adapter";
        vm.serializeString(adapter_, "name", adapterName);
        vm.serializeAddress(adapter_, "axelarGateway", vm.envAddress("AXELAR_GATEWAY"));
        string memory adaptersJson_ =
            vm.serializeAddress(adapter_, "axelarGasService", vm.envAddress("AXELAR_GAS_SERVICE"));

        string memory configJson_ = vm.serializeString(config_, "adapter", adaptersJson_);

        string memory contracts_ = "contracts";

        vm.serializeAddress(contracts_, "escrow", deployment_.escrow);
        vm.serializeAddress(contracts_, "routerEscrow", deployment_.routerEscrow);
        vm.serializeAddress(contracts_, "root", deployment_.root);
        vm.serializeAddress(contracts_, "router", deployment_.router);
        vm.serializeAddress(contracts_, "vaultFactory", deployment_.vaultFactory);
        vm.serializeAddress(contracts_, "trancheFactory", deployment_.trancheFactory);
        vm.serializeAddress(contracts_, "transferProxyFactory", deployment_.transferProxyFactory);
        vm.serializeAddress(contracts_, "poolManager", deployment_.poolManager);
        vm.serializeAddress(contracts_, "investmentManager", deployment_.investmentManager);
        vm.serializeAddress(contracts_, "restrictionManager", deployment_.restrictionManager);
        vm.serializeAddress(contracts_, "gasService", deployment_.gasService);
        vm.serializeAddress(contracts_, "gateway", deployment_.gateway);
        string memory contractsJson_ = vm.serializeAddress(contracts_, "guardian", deployment_.guardian);

        vm.serializeString(root_, "contracts", contractsJson_);
        vm.serializeString(root_, "config", configJson_);

        string memory json = vm.serializeUint(root_, "deploymentBlock", block.number);

        vm.writeJson(json, "./deployments/localnode.json");
    }

    function loadRawFromJson(string memory folder, string memory name) public returns (string memory rawJson) {
        Vm vm = new VmInstance().getVm();
        rawJson = vm.readFile(string.concat(vm.projectRoot(), "/deployments/", folder, "/", name, ".json"));
    }

    function loadFromJson(string memory folder, string memory name) public returns (Deployment memory deployment) {
        Vm vm = new VmInstance().getVm();
        deployment = _parse(vm.readFile(string.concat(vm.projectRoot(), "/deployments/", folder, "/", name, ".json")));
    }

    function _parse(string memory json) internal pure returns (Deployment memory deployment) {
        //TODO handle adapters;
        address[] memory adapters;
        Configuration memory configuration;
        configuration.delay = json.asUint(".config.delay");
        configuration.isTestnet = json.asBool(".config.isTestnet");

        /// @dev Initializing one by one instead initializing the whole struct
        /// so that I avoid ordering mistake
        /// Explicitly specifying the property allows us to not care about the order.
        /// Also if a property is replaced with new, the compiler will display the issue.
        deployment.escrow = json.asAddress(".contracts.escrow");
        deployment.routerEscrow = json.asAddress(".contracts.routerEscrow");
        deployment.root = json.asAddress(".contracts.root");
        deployment.vaultFactory = json.asAddress(".contracts.vaultFactory");
        deployment.trancheFactory = json.asAddress(".contracts.trancheFactory");
        deployment.transferProxyFactory = json.asAddress(".contracts.transferProxyFactory");
        deployment.poolManager = json.asAddress(".contracts.poolManager");
        deployment.investmentManager = json.asAddress(".contracts.investmentManager");
        deployment.restrictionManager = json.asAddress(".contracts.restrictionManager");
        deployment.router = json.asAddress(".contracts.router");
        deployment.gasService = json.asAddress(".contracts.gasService");
        deployment.gateway = payable(json.asAddress(".contracts.gateway"));
        deployment.guardian = json.asAddress(".contracts.guardian");
        deployment.deployer = json.asAddress(".config.deployer");
        deployment.adminSafe = json.asAddress(".config.admin");
        deployment.adapters = adapters;

        deployment.configuration = configuration;
    }
}
