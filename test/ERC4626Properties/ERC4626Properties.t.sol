pragma solidity ^0.8.0;

// import {CryticERC4626PropertyTests} from "properties/ERC4626PropertyTests.sol";
// this token _must_ be the vault's underlying asset
import {IERC20} from "src/interfaces/IERC20.sol";
import {PropertiesAsserts} from "./util/PropertiesAsserts.sol";
import {ERC4626PropertyBase} from "./ERC4626PropertyTestBase.sol";
import {TestERC20Token} from "./util/TestERC20Token.sol";

import "test/TestSetup.t.sol";

contract ERC4626PropertyTest is PropertiesAsserts, ERC4626PropertyBase, TestSetup {
    uint64 poolId;
    bytes16 trancheId;
    uint128 price;
    uint128 currencyId;

    function setUp() public override {
        super.setUp();
        poolId = 1;
        trancheId = bytes16(uint128(1));
        price = 1e27;
        currencyId = 1;
        string memory _name = "Test Token";
        string memory _symbol = "TT";
        uint8 _decimals = 18;
        TestERC20Token _asset = new TestERC20Token(_name, _symbol, _decimals);

        address _vault = deployLiquidityPool(poolId, _decimals, _name, _symbol, trancheId, currencyId, address(_asset));
        vm.prank(address(gateway));
        investmentManager.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);
        initialize(_vault, address(_asset), false);
    }
}
