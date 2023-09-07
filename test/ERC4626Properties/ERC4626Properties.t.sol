import {CryticERC4626PropertyTests} from "properties/ERC4626PropertyTests.sol";
// this token _must_ be the vault's underlying asset
import {TestERC20Token} from "properties/util/TestERC20Token.sol";

import "test/TestSetup.t.sol";

contract ERC4626PropertyTest is CryticERC4626PropertyTests, TestSetup {
    function setUp() public override {
        super.setUp();
        string memory _name = "Test Token";
        string memory _symbol = "TT";
        uint8 _decimals = 18;
        TestERC20Token _asset = new TestERC20Token(_name, _symbol, _decimals);
        uint64 _poolId = 1;
        bytes16 _trancheId = 0x0;

        address _vault = deployLiquidityPool(_poolId, _decimals, _name, _symbol, _trancheId, 0, address(_asset));
        initialize(_vault, address(_asset), false);
    }
}
