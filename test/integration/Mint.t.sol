// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../BaseTest.sol";

contract MintTest is BaseTest {
    function testMint(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);

        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        root.denyContract(address(trancheToken), self);

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        trancheToken.mint(investor, amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);

        vm.expectRevert(bytes("Auth/not-authorized"));
        trancheToken.mint(investor, amount);

        root.relyContract(address(trancheToken), self); // give self auth permissions

        // success
        trancheToken.mint(investor, amount);
        assertEq(trancheToken.balanceOf(investor), amount);
        assertEq(trancheToken.balanceOf(investor), trancheToken.balanceOf(investor));
    }
}
