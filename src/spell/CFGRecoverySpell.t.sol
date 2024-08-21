// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "./RecoveryController.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

interface iControllerProxy {
    function changeAdmin(address newAdmin) external;
    function upgradeTo(address implementation) external;
    function upgradeToAndCall(address newImplementation, bytes calldata data) external;
}

//     interface IERC20 {
//     function balanceOf(address account) external view returns (uint256);
//     function safeTransferFrom(address from, address to, uint256 value) external;
// }

contract RecoverySpellTest is Test {
    using stdJson for string;

    string[] deployments;
    RecoveryController recoveryController;

    address public constant ADMIN = 0xA014beAC6d27e442291773668de8b22585B0c455;
    address public constant CONTROLLER_IMPL_OLD = address(0x5EE834228165D6E9247F9944A158A2D9F0b52aFf);
    address public constant CONTROLLER_PROXY = address(0x77B59b07b87689a6D27adE063FB1D08C7Fe52F0b);

    address self;

    function setUp() public {
        self = address(this);
        _loadDeployment("mainnet", "ethereum-mainnet"); // Mainnet
        _loadFork(0);
    }

    function testRecovery() public {
        recoveryController = new RecoveryController(); // deploy new controller implementation
        uint256 vaultBalanceCFG = IERC20(recoveryController.WCFG()).balanceOf(recoveryController.RWA_VAULT());
        assertEq(vaultBalanceCFG, 138458952533663365715185);

        vm.startPrank(ADMIN);
        bytes memory data = abi.encodeWithSignature("recover()");
        iControllerProxy(CONTROLLER_PROXY).upgradeToAndCall(address(recoveryController), data);

        assertEq(IERC20(recoveryController.WCFG()).balanceOf(recoveryController.RECOVERY_WALLET()), vaultBalanceCFG);
        assertEq(IERC20(recoveryController.WCFG()).balanceOf(recoveryController.RWA_VAULT()), 0);
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
