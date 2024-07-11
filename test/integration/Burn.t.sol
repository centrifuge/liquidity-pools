// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "test/BaseTest.sol";

contract BurnTest is BaseTest {
    function testBurn(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);

        ITranche tranche = ITranche(address(vault.share()));
        root.relyContract(address(tranche), self); // give self auth permissions
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max); // add investor as
            // member

        tranche.mint(investor, amount);
        root.denyContract(address(tranche), self); // remove auth permissions from self

        vm.expectRevert(bytes("Auth/not-authorized"));
        tranche.burn(investor, amount);

        root.relyContract(address(tranche), self); // give self auth permissions
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        tranche.burn(investor, amount);

        // success
        vm.prank(investor);
        tranche.approve(self, amount); // approve to burn tokens
        tranche.burn(investor, amount);

        assertEq(tranche.balanceOf(investor), 0);
        assertEq(tranche.balanceOf(investor), tranche.balanceOf(investor));
    }
}
