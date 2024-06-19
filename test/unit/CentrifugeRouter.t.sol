// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";

contract CentrifugeRouterTest is BaseTest {
    function testGetVault() public {
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        assertEq(centrifugeRouter.getVault(vault.poolId(), vault.trancheId(), address(erc20)), vault_);
    }

    function testRecoverTokens() public {
        uint256 amount = 100;
        erc20.mint(address(centrifugeRouter), amount);
        vm.prank(address(root));
        centrifugeRouter.recoverTokens(address(erc20), address(this), amount);
        assertEq(erc20.balanceOf(address(this)), amount);
    }

    function testLockDepositRequests() public {
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");

        uint256 amount = 100 * 10 ** 18;
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);

        erc20.mint(self, amount);
        erc20.approve(address(centrifugeRouter), amount);

        vm.expectRevert("CentrifugeRouter/unknown-vault");
        centrifugeRouter.lockDepositRequest(makeAddr("maliciousVault"), amount, self, self);

        centrifugeRouter.lockDepositRequest(vault_, amount, self, self);

        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
    }
}
