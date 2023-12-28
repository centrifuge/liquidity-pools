// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";

contract Deployment is Test {
    using stdJson for string;

    // Metadata
    uint256 public chainId;
    string public rpcUrl;

    // Contracts
    address public root;
    address public investmentManager;
    address public poolManager;
    address public gateway;
    address public escrow;
    address public userEscrow;
    address public router;
    address public trancheTokenFactory;
    address public liquidityPoolFactory;
    address public restrictionManagerFactory;
    address public pauseAdmin;
    address public delayedAdmin;
    address public messages;
    
    // Config
    address public deployer;
    address public admin;
    address[] public pausers;

    constructor(string memory deploymentName) {
        string memory deployment = vm.readFile(string.concat(vm.projectRoot(), "/deployments/mainnet/", deploymentName, ".json"));

        chainId = abi.decode(deployment.parseRaw(".chainId"), (uint256));
        rpcUrl = abi.decode(deployment.parseRaw(".rpcUrl"), (string));

        root = abi.decode(deployment.parseRaw(".contracts.root"), (address));
        investmentManager = abi.decode(deployment.parseRaw(".contracts.investmentManager"), (address));
        poolManager = abi.decode(deployment.parseRaw(".contracts.poolManager"), (address));
        gateway = abi.decode(deployment.parseRaw(".contracts.gateway"), (address));
        escrow = abi.decode(deployment.parseRaw(".contracts.escrow"), (address));
        userEscrow = abi.decode(deployment.parseRaw(".contracts.userEscrow"), (address));
        router = abi.decode(deployment.parseRaw(".contracts.router"), (address));
        trancheTokenFactory = abi.decode(deployment.parseRaw(".contracts.trancheTokenFactory"), (address));
        liquidityPoolFactory = abi.decode(deployment.parseRaw(".contracts.liquidityPoolFactory"), (address));
        restrictionManagerFactory = abi.decode(deployment.parseRaw(".contracts.restrictionManagerFactory"), (address));
        pauseAdmin = abi.decode(deployment.parseRaw(".contracts.pauseAdmin"), (address));
        delayedAdmin = abi.decode(deployment.parseRaw(".contracts.delayedAdmin"), (address));
        messages = abi.decode(deployment.parseRaw(".contracts.messages"), (address));

        deployer = abi.decode(deployment.parseRaw(".config.deployer"), (address));
        admin = abi.decode(deployment.parseRaw(".config.admin"), (address));

        console.log("Loaded deployment %s (chain id: %s)", deploymentName, chainId);
        console.log("- root: $s", root);
    }
}
