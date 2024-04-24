pragma solidity 0.8.21;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

// core contracts
import {Root} from "../src/Root.sol";
import {InvestmentManager} from "../src/InvestmentManager.sol";
import {PoolManager, Tranche} from "../src/PoolManager.sol";
import {Escrow} from "../src/Escrow.sol";
import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {TrancheTokenFactory} from "src/factories/TrancheTokenFactory.sol";
import {ERC7540Vault} from "../src/ERC7540Vault.sol";
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
    MockRouter router1;
    MockRouter router2;
    MockRouter router3;
    address[] testRouters;
    ERC20 public erc20;

    address self = address(this);
    address investor = makeAddr("investor");
    address nonMember = makeAddr("nonMember");
    address randomUser = makeAddr("randomUser");

    uint128 constant MAX_UINT128 = type(uint128).max;

    // default values
    uint128 public defaultAssetId = 1;
    uint128 public defaultPrice = 1 * 10**18;
    uint8 public defaultRestrictionSet = 2;
    uint8 public defaultDecimals = 8;

    function setUp() public virtual {
        vm.chainId(1);

        // make yourself admin
        admin = self;

        // deploy core contracts
        deploy(address(this));

        // deploy mock routers
        router1 = new MockRouter(address(aggregator));
        router2 = new MockRouter(address(aggregator));
        router3 = new MockRouter(address(aggregator));

        testRouters.push(address(router1));
        testRouters.push(address(router2));
        testRouters.push(address(router3));

        // wire contracts
        wire(address(router1));
        aggregator.file("routers", testRouters);

        // give admin access
        giveAdminAccess();

        // remove deployer access
        // removeDeployerAccess(address(router)); // need auth permissions in tests

        centrifugeChain = new MockCentrifugeChain(testRouters);
        erc20 = _newErc20("X's Dollar", "USDX", 6);

        // Label contracts
        vm.label(address(root), "Root");
        vm.label(address(investmentManager), "InvestmentManager");
        vm.label(address(poolManager), "PoolManager");
        vm.label(address(gateway), "Gateway");
        vm.label(address(aggregator), "Aggregator");
        vm.label(address(router1), "MockRouter1");
        vm.label(address(router2), "MockRouter2");
        vm.label(address(router3), "MockRouter3");
        vm.label(address(erc20), "ERC20");
        vm.label(address(centrifugeChain), "CentrifugeChain");
        vm.label(address(escrow), "Escrow");
        vm.label(address(pauseAdmin), "PauseAdmin");
        vm.label(address(delayedAdmin), "DelayedAdmin");
        vm.label(address(poolManager.restrictionManagerFactory()), "RestrictionManagerFactory");
        vm.label(address(poolManager.trancheTokenFactory()), "TrancheTokenFactory");
        vm.label(address(poolManager.vaultFactory()), "ERC7540VaultFactory");

        // Exclude predeployed contracts from invariant tests by default
        excludeContract(address(root));
        excludeContract(address(investmentManager));
        excludeContract(address(poolManager));
        excludeContract(address(gateway));
        excludeContract(address(aggregator));
        excludeContract(address(erc20));
        excludeContract(address(centrifugeChain));
        excludeContract(address(router1));
        excludeContract(address(router2));
        excludeContract(address(router3));
        excludeContract(address(escrow));
        excludeContract(address(pauseAdmin));
        excludeContract(address(delayedAdmin));
        excludeContract(address(poolManager.restrictionManagerFactory()));
        excludeContract(address(poolManager.trancheTokenFactory()));
        excludeContract(address(poolManager.vaultFactory()));
    }

    // helpers
    function deployVault(
        uint64 poolId,
        uint8 trancheTokenDecimals,
        uint8 restrictionSet,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 assetId,
        address asset
    ) public returns (address) {
        if (poolManager.idToAsset(assetId) == address(0)) {
            centrifugeChain.addAsset(assetId, asset);
        }
        
        if (poolManager.getTrancheToken(poolId, trancheId) == address(0)) {
            centrifugeChain.addPool(poolId);
            centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, trancheTokenDecimals, restrictionSet);

            centrifugeChain.allowInvestmentCurrency(poolId, assetId);
            poolManager.deployTranche(poolId, trancheId);
        }

        if (!poolManager.isAllowedAsset(poolId, asset)) {
            centrifugeChain.allowInvestmentCurrency(poolId, assetId);
        }

        address vaultAddress = poolManager.deployVault(poolId, trancheId, asset);
        return vaultAddress;
    }

    function deployVault(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 asset
    ) public returns (address) {
        uint8 restrictionSet = 2;
        return deployVault(poolId, decimals, restrictionSet, tokenName, tokenSymbol, trancheId, asset, address(erc20));
    }

    function deploySimpleVault() public returns (address) {
        return deployVault(5, 6, defaultRestrictionSet, "name", "symbol", bytes16(bytes("1")), defaultAssetId, address(erc20));
    }

    function deposit(address _vault, address _investor, uint256 amount) public {
        deposit(_vault, _investor, amount, true);
    }

    function deposit(address _vault, address _investor, uint256 amount, bool claimDeposit) public {
        ERC7540Vault vault = ERC7540Vault(_vault);
        erc20.mint(_investor, amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), _investor, type(uint64).max); // add user as member
        vm.startPrank(_investor);
        erc20.approve(_vault, amount); // add allowance
        vault.requestDeposit(amount, _investor, _investor, "");
        // trigger executed collectInvest
        uint128 assetId = poolManager.assetToId(address(erc20)); // retrieve assetId
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(_investor)),
            assetId,
            uint128(amount),
            uint128(amount),
            0
        );

        if (claimDeposit) {
           vault.deposit(amount, _investor); // claim the trancheTokens
        }
        vm.stopPrank();
    }

    // Helpers
    function _addressToBytes32(address x) internal pure returns (bytes32) {
        return bytes32(bytes20(x));
    }

    function _newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 asset = new ERC20(decimals);
        asset.file("name", name);
        asset.file("symbol", symbol);
        return asset;
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
