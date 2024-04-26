// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../BaseTest.sol";

contract BurnTest is BaseTest {
    function testBurn(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);

        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        root.relyContract(address(trancheToken), self); // give self auth permissions
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max); // add investor as
            // member

        trancheToken.mint(investor, amount);
        root.denyContract(address(trancheToken), self); // remove auth permissions from self

        vm.expectRevert(bytes("Auth/not-authorized"));
        trancheToken.burn(investor, amount);

        root.relyContract(address(trancheToken), self); // give self auth permissions
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        trancheToken.burn(investor, amount);

        // success
        vm.prank(investor);
        trancheToken.approve(self, amount); // approve to burn tokens
        trancheToken.burn(investor, amount);

        assertEq(trancheToken.balanceOf(investor), 0);
        assertEq(trancheToken.balanceOf(investor), trancheToken.balanceOf(investor));
    }
}
