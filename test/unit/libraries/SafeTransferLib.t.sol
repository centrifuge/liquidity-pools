// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

/// @dev Token not returning any boolean.
contract ERC20WithoutBoolean {
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public balanceOf;

    function transfer(address to, uint256 amount) public {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) public {
        // Skip allowance check.
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 value) public {
        allowance[msg.sender][spender] = value;
    }

    function setBalance(address account, uint256 amount) public {
        balanceOf[account] = amount;
    }
}

/// @dev Token always returning false.
contract ERC20WithBooleanAlwaysFalse {
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public balanceOf;

    function transfer(address to, uint256 amount) public returns (bool failure) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        failure = false; // To silence warning.
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool failure) {
        // Skip allowance check.
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        failure = false; // To silence warning.
    }

    function approve(address spender, uint256 value) public returns (bool failure) {
        allowance[msg.sender][spender] = value;
        failure = false; // To silence warning
    }

    function setBalance(address account, uint256 amount) public {
        balanceOf[account] = amount;
    }
}

/// @author Modified from
/// https://github.com/morpho-org/morpho-blue/blob/main/test/forge/libraries/SafeTransferLibTest.sol
contract SafeTransferLibTest is Test {
    ERC20WithoutBoolean public tokenWithoutBoolean;
    ERC20WithBooleanAlwaysFalse public tokenWithBooleanAlwaysFalse;

    function setUp() public {
        tokenWithoutBoolean = new ERC20WithoutBoolean();
        tokenWithBooleanAlwaysFalse = new ERC20WithBooleanAlwaysFalse();
    }

    function testSafeTransfer(address to, uint256 amount) public {
        tokenWithoutBoolean.setBalance(address(this), amount);

        this.safeTransfer(address(tokenWithoutBoolean), to, amount);
    }

    function testSafeTransferFrom(address from, address to, uint256 amount) public {
        tokenWithoutBoolean.setBalance(from, amount);

        this.safeTransferFrom(address(tokenWithoutBoolean), from, to, amount);
    }

    function testApprove(address spender, uint256 amount) public {
        this.safeApprove(address(tokenWithoutBoolean), spender, amount);
    }

    function testSafeTransferWithBoolFalse(address to, uint256 amount) public {
        tokenWithBooleanAlwaysFalse.setBalance(address(this), amount);

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-failed"));
        this.safeTransfer(address(tokenWithBooleanAlwaysFalse), to, amount);
    }

    function testSafeTransferFromWithBoolFalse(address from, address to, uint256 amount) public {
        tokenWithBooleanAlwaysFalse.setBalance(from, amount);

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        this.safeTransferFrom(address(tokenWithBooleanAlwaysFalse), from, to, amount);
    }

    function testSafeApproveWithBoolFalse(address spender, uint256 amount) public {
        vm.expectRevert(bytes("SafeTransferLib/safe-approve-failed"));
        this.safeApprove(address(tokenWithBooleanAlwaysFalse), spender, amount);
    }

    function safeTransfer(address token, address to, uint256 amount) external {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) external {
        SafeTransferLib.safeTransferFrom(token, from, to, amount);
    }

    function safeApprove(address token, address spender, uint256 amount) external {
        SafeTransferLib.safeApprove(token, spender, amount);
    }
}
