// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager} from "../src/InvestmentManager.sol";
import {PoolManager, Tranche} from "../src/PoolManager.sol";
import {Gateway} from "../src/gateway/Gateway.sol";
import {Root} from "../src/Root.sol";
import {Escrow} from "../src/Escrow.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "../src/util/Factory.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {ERC20} from "../src/token/ERC20.sol";
import {TrancheToken} from "../src/token/Tranche.sol";

import {MemberlistLike, Memberlist} from "../src/token/Memberlist.sol";
import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {Messages} from "../src/gateway/Messages.sol";
import "forge-std/Test.sol";
import "../src/InvestmentManager.sol";

interface EscrowLike_ {
    function approve(address token, address spender, uint256 value) external;
    function rely(address usr) external;
}

contract PoolManagerTest is Test {
    InvestmentManager evmInvestmentManager;
    PoolManager evmPoolManager;
    Gateway gateway;
    MockHomeLiquidityPools homePools;
    MockXcmRouter mockXcmRouter;

    function setUp() public {
        vm.chainId(1);
        address escrow_ = address(new Escrow());
        address root_ = address(new Root(address(escrow_), 48 hours));
        LiquidityPoolFactory liquidityPoolFactory_ = new LiquidityPoolFactory(root_);
        TrancheTokenFactory trancheTokenFactory_ = new TrancheTokenFactory(root_);

        evmInvestmentManager = new InvestmentManager(escrow_);
        evmPoolManager = new PoolManager(escrow_, address(liquidityPoolFactory_), address(trancheTokenFactory_));
        liquidityPoolFactory_.rely(address(evmPoolManager));
        trancheTokenFactory_.rely(address(evmPoolManager));

        mockXcmRouter = new MockXcmRouter(address(evmInvestmentManager));

        homePools = new MockHomeLiquidityPools(address(mockXcmRouter));

        gateway = new Gateway(root_, address(evmInvestmentManager), address(evmPoolManager), address(mockXcmRouter));
        evmInvestmentManager.file("gateway", address(gateway));
        evmInvestmentManager.file("poolManager", address(evmPoolManager));
        evmPoolManager.file("gateway", address(gateway));
        evmPoolManager.file("investmentManager", address(evmInvestmentManager));
        EscrowLike_(escrow_).rely(address(evmInvestmentManager));
        EscrowLike_(escrow_).rely(address(evmPoolManager));
        mockXcmRouter.file("gateway", address(gateway));
        evmInvestmentManager.rely(address(gateway));
        evmInvestmentManager.rely(address(evmPoolManager));
        Escrow(escrow_).rely(address(gateway));
    }

    function testAddCurrencyWorks(uint128 currency, uint128 badCurrency) public {
        vm.assume(currency > 0);
        vm.assume(badCurrency > 0);
        vm.assume(currency != badCurrency);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addCurrency(currency, address(erc20));
        (address address_) = evmPoolManager.currencyIdToAddress(currency);
        assertEq(address_, address(erc20));

        // Verify we can't override the same currency id another address
        ERC20 badErc20 = newErc20("BadActor's Dollar", "BADUSD", 18);
        vm.expectRevert(bytes("PoolManager/currency-id-in-use"));
        homePools.addCurrency(currency, address(badErc20));
        assertEq(evmPoolManager.currencyIdToAddress(currency), address(erc20));

        // Verify we can't add a currency address that already exists associated with a different currency id
        vm.expectRevert(bytes("PoolManager/currency-address-in-use"));
        homePools.addCurrency(badCurrency, address(erc20));
        assertEq(evmPoolManager.currencyIdToAddress(currency), address(erc20));
    }

    function testAddCurrencyHasMaxDecimals() public {
        ERC20 erc20_invalid = newErc20("X's Dollar", "USDX", 42);
        vm.expectRevert(bytes("PoolManager/too-many-currency-decimals"));
        homePools.addCurrency(1, address(erc20_invalid));

        ERC20 erc20_valid = newErc20("X's Dollar", "USDX", 18);
        homePools.addCurrency(2, address(erc20_valid));

        ERC20 erc20_valid2 = newErc20("X's Dollar", "USDX", 6);
        homePools.addCurrency(3, address(erc20_valid2));
    }

    function testIncomingTransferWithoutEscrowFundsFails(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        vm.assume(decimals > 0);
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        vm.assume(amount > 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        vm.assume(recipient != address(erc20));
        homePools.addCurrency(currency, address(erc20));

        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        homePools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), 0);
    }

    function testIncomingTransferWorks(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        vm.assume(decimals > 0);
        vm.assume(decimals <= 18);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        homePools.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(evmPoolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        evmPoolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), amount);

        // Now we test the incoming message
        homePools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    // Verify that funds are moved from the msg.sender into the escrow account
    function testOutgoingTransferWorks(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 initialBalance,
        uint128 currency,
        bytes32 recipient,
        uint128 amount
    ) public {
        vm.assume(decimals > 0);
        vm.assume(decimals <= 18);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(initialBalance >= amount);

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);

        vm.expectRevert(bytes("PoolManager/unknown-currency"));
        evmPoolManager.transfer(address(erc20), recipient, amount);
        homePools.addCurrency(currency, address(erc20));

        erc20.mint(address(this), initialBalance);
        assertEq(erc20.balanceOf(address(this)), initialBalance);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
        erc20.approve(address(evmPoolManager), type(uint256).max);

        evmPoolManager.transfer(address(erc20), recipient, amount);
        assertEq(erc20.balanceOf(address(this)), initialBalance - amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), amount);
    }

    function testTransferTrancheTokensToCentrifuge(
        uint64 validUntil,
        bytes32 centChainAddress,
        uint128 amount,
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currency);
        homePools.updateMember(poolId, trancheId, address(this), validUntil);

        // fund this account with amount
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), address(this), amount);

        // Verify the address(this) has the expected amount
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), amount);

        // Now send the transfer from EVM -> Cent Chain
        LiquidityPool(lPool_).approve(address(evmPoolManager), amount);
        evmPoolManager.transferTrancheTokensToCentrifuge(poolId, trancheId, centChainAddress, amount);
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), 0);

        // Finally, verify the connector called `router.send`
        bytes memory message = Messages.formatTransferTrancheTokens(
            poolId,
            trancheId,
            bytes32(bytes20(address(this))),
            Messages.formatDomain(Messages.Domain.Centrifuge),
            centChainAddress,
            amount
        );
        assertEq(mockXcmRouter.sentMessages(message), true);
    }

    function testTransferTrancheTokensFromCentrifuge(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency,
        uint64 validUntil,
        address destinationAddress,
        uint128 amount
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(validUntil >= block.timestamp);
        vm.assume(destinationAddress != address(0));
        vm.assume(currency > 0);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currency);

        homePools.updateMember(poolId, trancheId, destinationAddress, validUntil);
        assertTrue(LiquidityPool(lPool_).hasMember(destinationAddress));
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
        assertEq(LiquidityPoolLike(lPool_).balanceOf(destinationAddress), amount);
    }

    function testTransferTrancheTokensFromCentrifugeWithoutMemberFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency,
        address destinationAddress,
        uint128 amount
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(destinationAddress != address(0));
        vm.assume(currency > 0);

        deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currency);

        vm.expectRevert(bytes("PoolManager/not-a-member"));
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
    }

    function testTransferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint64 validUntil,
        address destinationAddress,
        uint128 amount,
        uint128 currency
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(destinationAddress != address(0));
        vm.assume(currency > 0);
        vm.assume(amount > 0);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currency);
        homePools.updateMember(poolId, trancheId, destinationAddress, validUntil);
        homePools.updateMember(poolId, trancheId, address(this), validUntil);
        assertTrue(LiquidityPool(lPool_).hasMember(address(this)));
        assertTrue(LiquidityPool(lPool_).hasMember(destinationAddress));

        // Fund this address with amount
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), address(this), amount);
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), amount);

        // Approve and transfer amount from this address to destinationAddress
        LiquidityPool(lPool_).approve(address(evmPoolManager), amount);
        console.logAddress(lPool_);
        console.logAddress(LiquidityPool(lPool_).asset());
        evmPoolManager.transferTrancheTokensToEVM(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), 0);
    }

    function testUpdatingMemberWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        address user,
        uint64 validUntil,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);
        address lPool_ = evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        homePools.updateMember(poolId, trancheId, user, validUntil);
        assertTrue(LiquidityPool(lPool_).hasMember(user));
    }

    function testUpdatingMemberAsNonRouterFails(
        uint64 poolId,
        uint128 currency,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));
        vm.assume(currency > 0);

        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmPoolManager.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp);
        homePools.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        homePools.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingTokenPriceWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        vm.assume(poolId > 0);
        vm.assume(trancheId > 0);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        address tranche_ = evmPoolManager.deployTranche(poolId, trancheId);

        homePools.updateTrancheTokenPrice(poolId, trancheId, price);
        assertEq(TrancheToken(tranche_).latestPrice(), price);
        assertEq(TrancheToken(tranche_).lastPriceUpdate(), block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);
        evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmPoolManager.updateTrancheTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        homePools.updateTrancheTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenMetadataWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        string memory updatedTokenName,
        string memory updatedTokenSymbol
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        evmPoolManager.deployTranche(poolId, trancheId);

        homePools.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);
    }

    function testUpdatingTokenMetadataAsNonRouterFails(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        string memory updatedTokenName,
        string memory updatedTokenSymbol
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);
        evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmPoolManager.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);
    }

    function testUpdatingTokenMetadataForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory updatedTokenName,
        string memory updatedTokenSymbol
    ) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        homePools.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);
    }

    // helpers
    function deployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency
    ) internal returns (address lPool) {
        // deploy liquidityPool
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, 0); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);

        evmPoolManager.deployTranche(poolId, trancheId);
        lPool = evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
    }

    function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 erc20 = new ERC20(decimals);
        erc20.file("name", name);
        erc20.file("symbol", symbol);

        return erc20;
    }

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
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

    function toBytes32(bytes memory f) internal pure returns (bytes16 fc) {
        assembly {
            fc := mload(add(f, 32))
        }
        return fc;
    }

    function hasDuplicates(bytes16[] calldata array) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (array[i] == array[j]) {
                    return true;
                }
            }
        }
        return false;
    }
}
