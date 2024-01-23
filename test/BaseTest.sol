pragma solidity 0.8.21;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

// core contracts
import {Root} from "../src/Root.sol";
import {InvestmentManager} from "../src/InvestmentManager.sol";
import {PoolManager, Tranche} from "../src/PoolManager.sol";
import {Escrow} from "../src/Escrow.sol";
import {UserEscrow} from "../src/UserEscrow.sol";
import {LiquidityPoolFactory} from "src/factories/LiquidityPoolFactory.sol";
import {TrancheTokenFactory} from "src/factories/TrancheTokenFactory.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {TrancheToken, TrancheTokenLike} from "../src/token/Tranche.sol";
import {ERC20} from "../src/token/ERC20.sol";
import {Gateway} from "../src/gateway/Gateway.sol";
import {RestrictionManagerLike, RestrictionManager} from "../src/token/RestrictionManager.sol";
import {MessagesLib} from "../src/libraries/MessagesLib.sol";
import {Deployer} from "../script/Deployer.sol";
import "../src/interfaces/IERC20.sol";

// mocks
import {MockCentrifugeChain} from "./mocks/MockCentrifugeChain.sol";
import {MockRouter} from "./mocks/MockRouter.sol";

// test env
import "forge-std/Test.sol";

contract BaseTest is Deployer, Test {
    MockCentrifugeChain centrifugeChain;
    MockRouter router;
    ERC20 public erc20;

    address self = address(this);
    address investor = makeAddr("investor");
    address nonMember = makeAddr("nonMember");
    address randomUser = makeAddr("randomUser");

    uint128 constant MAX_UINT128 = type(uint128).max;

    // default values
    uint128 public defaultCurrencyId = 1;
    uint128 public defaultPrice = 1 * 10**18;
    uint8 public defaultRestrictionSet = 2;
    uint8 public defaultDecimals = 8;

    function setUp() public virtual {
        vm.chainId(1);

        // make yourself admin
        admin = self;

        // deploy core contracts
        deployInvestmentManager(address(this));
        // deploy mockRouter
        router = new MockRouter(address(investmentManager));
        // wire contracts
        wire(address(router));
        // give admin access
        giveAdminAccess();
        // remove deployer access
        // removeDeployerAccess(address(router)); // need auth permissions in tests

        centrifugeChain = new MockCentrifugeChain(address(router));
        erc20 = _newErc20("X's Dollar", "USDX", 6);
        router.file("gateway", address(gateway));

        // Exclude predeployed contracts from invariant tests by default
        excludeContract(address(root));
        excludeContract(address(investmentManager));
        excludeContract(address(poolManager));
        excludeContract(address(gateway));
        excludeContract(address(erc20));
        excludeContract(address(centrifugeChain));
        excludeContract(address(router));
        excludeContract(address(escrow));
        excludeContract(address(userEscrow));
        excludeContract(address(pauseAdmin));
        excludeContract(address(delayedAdmin));
        excludeContract(address(poolManager.restrictionManagerFactory()));
        excludeContract(address(poolManager.trancheTokenFactory()));
        excludeContract(address(poolManager.liquidityPoolFactory()));
    }

    // helpers
    function deployLiquidityPool(
        uint64 poolId,
        uint8 trancheTokenDecimals,
        uint8 restrictionSet,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        address currency
    ) public returns (address) {
        if (poolManager.currencyIdToAddress(currencyId) == address(0)) {
            centrifugeChain.addCurrency(currencyId, currency);
        }
        
        if (poolManager.getTrancheToken(poolId, trancheId) == address(0)) {
            centrifugeChain.addPool(poolId);
            centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, trancheTokenDecimals, restrictionSet);

            centrifugeChain.allowInvestmentCurrency(poolId, currencyId);
            poolManager.deployTranche(poolId, trancheId);
        }

        if (!poolManager.isAllowedAsInvestmentCurrency(poolId, currency)) {
            centrifugeChain.allowInvestmentCurrency(poolId, currencyId);
        }

        address lPoolAddress = poolManager.deployLiquidityPool(poolId, trancheId, currency);
        return lPoolAddress;
    }

    function deployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency
    ) public returns (address) {
        uint8 restrictionSet = 2;
        return deployLiquidityPool(poolId, decimals, restrictionSet, tokenName, tokenSymbol, trancheId, currency, address(erc20));
    }

    function deploySimplePool() public returns (address) {
        return deployLiquidityPool(5, 6, defaultRestrictionSet, "name", "symbol", _stringToBytes16("1"), defaultCurrencyId, address(erc20));
    }

    function deposit(address _lPool, address _investor, uint256 amount) public {
        deposit(_lPool, _investor, amount, true);
    }

    function deposit(address _lPool, address _investor, uint256 amount, bool claimDeposit) public {
        LiquidityPool lPool = LiquidityPool(_lPool);
        erc20.mint(_investor, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), _investor, type(uint64).max); // add user as member
        vm.startPrank(_investor);
        erc20.approve(_lPool, amount); // add allowance
        lPool.requestDeposit(amount, _investor, _investor, "");
        // trigger executed collectInvest
        uint128 currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(_investor)),
            currencyId,
            uint128(amount),
            uint128(amount),
            0
        );

        if (claimDeposit) {
           lPool.deposit(amount, _investor); // claim the trancheTokens
        }
        vm.stopPrank();
    }

    // Helpers
    function _addressToBytes32(address x) internal pure returns (bytes32) {
        return bytes32(bytes20(x));
    }

    function _newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 currency = new ERC20(decimals);
        currency.file("name", name);
        currency.file("symbol", symbol);
        return currency;
    }

    function _stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function _stringToBytes16(string memory source) internal pure returns (bytes16 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 16))
        }
    }

    function _bytes16ToString(bytes16 _bytes16) public pure returns (string memory) {
        uint8 i = 0;
        while(i < 16 && _bytes16[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 16 && _bytes16[i] != 0; i++) {
            bytesArray[i] = _bytes16[i];
        }
        return string(bytesArray);
    }

    function _bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function _stringToBytes128(string memory source) internal pure returns (bytes memory) {
        bytes memory temp = bytes(source);
        bytes memory result = new bytes(128);

        for (uint256 i = 0; i < 128; i++) {
            if (i < temp.length) {
                result[i] = temp[i];
            } else {
                result[i] = 0x00;
            }
        }

        return result;
    }

    function _bytes128ToString(bytes memory _bytes128) internal pure returns (string memory) {
        require(_bytes128.length == 128, "Input should be 128 bytes");

        uint8 i = 0;
        while (i < 128 && _bytes128[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);

        for (uint8 j = 0; j < i; j++) {
            bytesArray[j] = _bytes128[j];
        }

        return string(bytesArray);
    }

    function _uint256ToString(uint _i) internal pure returns (string memory _uintAsString) {
            if (_i == 0) {
                return "0";
            }
            uint j = _i;
            uint len;
            while (j != 0) {
                len++;
                j /= 10;
            }
            bytes memory bstr = new bytes(len);
            uint k = len;
            while (_i != 0) {
                k = k-1;
                uint8 temp = (48 + uint8(_i - _i / 10 * 10));
                bytes1 b1 = bytes1(temp);
                bstr[k] = b1;
                _i /= 10;
            }
            return string(bstr);
        }

    function random(uint256 maxValue, uint256 nonce) internal view returns (uint256) {
        if (maxValue == 1) {
            return maxValue;
        }
        uint256 randomnumber = uint256(keccak256(abi.encodePacked(block.timestamp, self, nonce))) % (maxValue - 1);
        return randomnumber + 1;
    }

    // assumptions
    function amountAssumption(uint256 amount) public pure returns (bool) {
        return (amount > 1 && amount < MAX_UINT128);
    }

    function addressAssumption(address user) public view returns (bool) {
        return (user != address(0) && user != address(erc20) && user.code.length == 0);
    }
}
