// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../TestSetup.t.sol";

contract BurnTest is TestSetup {
    function testBurn(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));
        root.relyContract(address(trancheToken), self); // give self auth permissions
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max); // add investor as
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
        lPool.approve(self, amount); // approve to burn tokens
        trancheToken.burn(investor, amount);

        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(investor), trancheToken.balanceOf(investor));
    }
}
