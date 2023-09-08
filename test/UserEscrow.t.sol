// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {UserEscrow} from "src/UserEscrow.sol";
import "./TestSetup.t.sol";

interface ERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

contract userEscrowTest is TestSetup {
    function testTransferIn(uint256 mintAmount, uint256 amount) public {
        vm.assume(mintAmount >= amount);
        vm.assume(amount > 0);
        address erc20_ = address(erc20);
        address source = address(0xCAFE);
        address destination = address(0xBEEF);

        erc20.mint(source, mintAmount);

        assertEq(erc20.balanceOf(source), mintAmount);
        assertEq(erc20.balanceOf(destination), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), 0);

        vm.prank(source);
        erc20.approve(address(userEscrow), amount);
        userEscrow.transferIn(erc20_, source, destination, amount);

        assertEq(erc20.balanceOf(source), mintAmount - amount);
        assertEq(erc20.balanceOf(destination), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), amount);
    }

    function testTransferOutToDestination(uint256 mintAmount, uint256 amountIn, uint256 amountOut) public {
        vm.assume(mintAmount >= amountIn);
        vm.assume(amountIn >= amountOut);
        vm.assume(amountOut > 0);
        address erc20_ = address(erc20);
        address source = address(0xCAFE);
        address destination = address(0xBEEF);

        erc20.mint(source, mintAmount);

        assertEq(erc20.balanceOf(source), mintAmount);
        assertEq(erc20.balanceOf(destination), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), 0);

        vm.prank(source);
        erc20.approve(address(userEscrow), amountIn);
        userEscrow.transferIn(erc20_, source, destination, amountIn);

        assertEq(erc20.balanceOf(source), mintAmount - amountIn);
        assertEq(erc20.balanceOf(destination), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), amountIn);

        userEscrow.transferOut(erc20_, destination, destination, amountOut);

        assertEq(erc20.balanceOf(source), mintAmount - amountIn);
        assertEq(erc20.balanceOf(destination), amountOut);
        assertEq(erc20.balanceOf(address(userEscrow)), amountIn - amountOut);
    }

    function testTransferOutToNotDestination(uint256 mintAmount, uint256 amountIn, uint256 amountOut) public {
        vm.assume(mintAmount >= amountIn);
        vm.assume(amountIn >= amountOut);
        vm.assume(amountOut > 0);
        vm.assume(amountOut < type(uint256).max);
        address erc20_ = address(erc20);
        address source = address(0xCAFE);
        address destination = address(0xBEEF);
        address otherDestination = address(0xBEEF2);

        erc20.mint(source, mintAmount);

        assertEq(erc20.balanceOf(source), mintAmount);
        assertEq(erc20.balanceOf(destination), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), 0);

        vm.prank(source);
        erc20.approve(address(userEscrow), amountIn);
        userEscrow.transferIn(erc20_, source, destination, amountIn);

        assertEq(erc20.balanceOf(source), mintAmount - amountIn);
        assertEq(erc20.balanceOf(destination), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), amountIn);

        vm.expectRevert("UserEscrow/receiver-has-no-allowance");
        userEscrow.transferOut(erc20_, destination, otherDestination, amountOut);

        vm.prank(destination);
        erc20.approve(address(otherDestination), amountOut);
        vm.expectRevert("UserEscrow/receiver-has-no-allowance");
        userEscrow.transferOut(erc20_, destination, otherDestination, amountOut);

        vm.prank(destination);
        erc20.approve(address(otherDestination), type(uint256).max);
        userEscrow.transferOut(erc20_, destination, otherDestination, amountOut);

        assertEq(erc20.balanceOf(source), mintAmount - amountIn);
        assertEq(erc20.balanceOf(destination), 0);
        assertEq(erc20.balanceOf(otherDestination), amountOut);
        assertEq(erc20.balanceOf(address(userEscrow)), amountIn - amountOut);
    }

    function testMultipleTransfersIn() public {
        address erc20_ = address(erc20);
        address source = address(0xCAFE);
        address destination = address(0xBEEF);
        uint256 mintAmount = 1000;
        erc20.mint(source, mintAmount);

        vm.prank(source);
        erc20.approve(address(userEscrow), mintAmount);

        userEscrow.transferIn(erc20_, source, destination, 10);
        userEscrow.transferIn(erc20_, source, destination, 20);
        userEscrow.transferOut(erc20_, destination, destination, 30);

        vm.expectRevert("UserEscrow/transfer-failed");
        userEscrow.transferOut(erc20_, destination, destination, 1);

        assertEq(erc20.balanceOf(destination), 30);
    }

    function testMultipleTransfersOut() public {
        address erc20_ = address(erc20);
        address source = address(0xCAFE);
        address destination = address(0xBEEF);
        uint256 mintAmount = 1000;
        erc20.mint(source, mintAmount);

        vm.prank(source);
        erc20.approve(address(userEscrow), mintAmount);
        userEscrow.transferIn(erc20_, source, destination, 30);
        userEscrow.transferOut(erc20_, destination, destination, 20);
        userEscrow.transferOut(erc20_, destination, destination, 10);

        vm.expectRevert("UserEscrow/transfer-failed");
        userEscrow.transferOut(erc20_, destination, destination, 1);

        assertEq(erc20.balanceOf(destination), 30);
    }
}
