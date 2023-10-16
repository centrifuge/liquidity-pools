// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../TestSetup.t.sol";

contract MintTest is TestSetup {
    function testMint(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));
        root.denyContract(address(trancheToken), self);

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        trancheToken.mint(investor, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max);

        vm.expectRevert(bytes("Auth/not-authorized"));
        trancheToken.mint(investor, amount);

        root.relyContract(address(trancheToken), self); // give self auth permissions

        // success
        trancheToken.mint(investor, amount);
        assertEq(lPool.balanceOf(investor), amount);
        assertEq(lPool.balanceOf(investor), trancheToken.balanceOf(investor));
    }
}
