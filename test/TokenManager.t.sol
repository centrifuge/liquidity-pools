// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager, Tranche} from "../src/InvestmentManager.sol";
import {TokenManager} from "../src/TokenManager.sol";
import {Gateway} from "../src/Gateway.sol";
import {Escrow} from "../src/Escrow.sol";
import {LiquidityPoolFactory, MemberlistFactory, TrancheTokenFactory} from "../src/liquidityPool/Factory.sol";
import {LiquidityPool} from "../src/liquidityPool/LiquidityPool.sol";
import {ERC20} from "../src/token/ERC20.sol";
import {TrancheToken} from "../src/token/Tranche.sol";

import {MemberlistLike, Memberlist} from "../src/token/Memberlist.sol";
import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {Messages} from "../src/Messages.sol";
import {PauseAdmin} from "../src/admin/PauseAdmin.sol";
import {DelayedAdmin} from "../src/admin/DelayedAdmin.sol";
import "forge-std/Test.sol";
import "../src/InvestmentManager.sol";

interface EscrowLike_ {
    function approve(address token, address spender, uint256 value) external;
    function rely(address usr) external;
}

contract TokenManagerTest is Test {
    InvestmentManager evmInvestmentManager;
    TokenManager evmTokenManager;
    Gateway gateway;
    MockHomeLiquidityPools homePools;
    MockXcmRouter mockXcmRouter;

    function setUp() public {
        vm.chainId(1);
        uint256 shortWait = 24 hours;
        uint256 longWait = 48 hours;
        uint256 gracePeriod = 48 hours;
        address escrow_ = address(new Escrow());
        address liquidityPoolFactory_ = address(new LiquidityPoolFactory());
        address trancheTokenFactory_ = address(new TrancheTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        evmInvestmentManager =
            new InvestmentManager(escrow_, liquidityPoolFactory_, trancheTokenFactory_, memberlistFactory_);
        evmTokenManager = new TokenManager(escrow_);

        mockXcmRouter = new MockXcmRouter(address(evmInvestmentManager));

        homePools = new MockHomeLiquidityPools(address(mockXcmRouter));
        PauseAdmin pauseAdmin = new PauseAdmin();
        DelayedAdmin delayedAdmin = new DelayedAdmin();

        gateway =
        new Gateway(address(evmInvestmentManager), address(evmTokenManager), address(mockXcmRouter), shortWait, longWait, gracePeriod);
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        evmInvestmentManager.file("gateway", address(gateway));
        evmInvestmentManager.file("tokenManager", address(evmTokenManager));
        evmTokenManager.file("gateway", address(gateway));
        evmTokenManager.file("investmentManager", address(evmInvestmentManager));
        EscrowLike_(escrow_).rely(address(evmInvestmentManager));
        EscrowLike_(escrow_).rely(address(evmTokenManager));
        mockXcmRouter.file("gateway", address(gateway));
        evmInvestmentManager.rely(address(gateway));
        Escrow(escrow_).rely(address(gateway));
    }

    function testAddCurrencyWorks(uint128 currency, uint128 badCurrency) public {
        vm.assume(currency > 0);
        vm.assume(badCurrency > 0);
        vm.assume(currency != badCurrency);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addCurrency(currency, address(erc20));
        (address address_) = evmTokenManager.currencyIdToAddress(currency);
        assertEq(address_, address(erc20));

        // Verify we can't override the same currency id another address
        ERC20 badErc20 = newErc20("BadActor's Dollar", "BADUSD", 66);
        vm.expectRevert(bytes("TokenManager/currency-id-in-use"));
        homePools.addCurrency(currency, address(badErc20));
        assertEq(evmTokenManager.currencyIdToAddress(currency), address(erc20));

        // Verify we can't add a currency address that already exists associated with a different currency id
        vm.expectRevert(bytes("TokenManager/currency-address-in-use"));
        homePools.addCurrency(badCurrency, address(erc20));
        assertEq(evmTokenManager.currencyIdToAddress(currency), address(erc20));
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
        vm.assume(currency > 0);
        vm.assume(amount > 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        vm.assume(recipient != address(erc20));
        homePools.addCurrency(currency, address(erc20));

        assertEq(erc20.balanceOf(address(evmTokenManager.escrow())), 0);
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        homePools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmTokenManager.escrow())), 0);
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
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        homePools.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(evmTokenManager), type(uint256).max);
        erc20.mint(address(this), amount);
        evmTokenManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmTokenManager.escrow())), amount);

        // Now we test the incoming message
        homePools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmTokenManager.escrow())), 0);
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
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(initialBalance >= amount);

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);

        vm.expectRevert(bytes("TokenManager/unknown-currency"));
        evmTokenManager.transfer(address(erc20), recipient, amount);
        homePools.addCurrency(currency, address(erc20));

        erc20.mint(address(this), initialBalance);
        assertEq(erc20.balanceOf(address(this)), initialBalance);
        assertEq(erc20.balanceOf(address(evmTokenManager.escrow())), 0);
        erc20.approve(address(evmTokenManager), type(uint256).max);

        evmTokenManager.transfer(address(erc20), recipient, amount);
        assertEq(erc20.balanceOf(address(this)), initialBalance - amount);
        assertEq(erc20.balanceOf(address(evmTokenManager.escrow())), amount);
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
        vm.assume(currency > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currency);
        homePools.updateMember(poolId, trancheId, address(this), validUntil);

        // fund this account with amount
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), address(this), amount);

        // Verify the address(this) has the expected amount
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), amount);

        // Now send the transfer from EVM -> Cent Chain
        LiquidityPool(lPool_).approve(address(evmTokenManager), amount);
        evmTokenManager.transferTrancheTokensToCentrifuge(poolId, trancheId, centChainAddress, amount);
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
        vm.assume(destinationAddress != address(0));
        vm.assume(currency > 0);

        deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currency);

        vm.expectRevert(bytes("TokenManager/not-a-member"));
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
        LiquidityPool(lPool_).approve(address(evmTokenManager), amount);
        console.logAddress(lPool_);
        console.logAddress(LiquidityPool(lPool_).asset());
        evmTokenManager.transferTrancheTokensToEVM(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
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
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmInvestmentManager.deployTranche(poolId, trancheId);
        address lPool_ = evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));

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

        vm.expectRevert(bytes("TokenManager/not-the-gateway"));
        evmTokenManager.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp);
        homePools.addPool(poolId);

        vm.expectRevert(bytes("TokenManager/unknown-token"));
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
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        address tranche_ = evmInvestmentManager.deployTranche(poolId, trancheId);

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
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmInvestmentManager.deployTranche(poolId, trancheId);
        evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("TokenManager/not-the-gateway"));
        evmTokenManager.updateTrancheTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("TokenManager/unknown-token"));
        homePools.updateTrancheTokenPrice(poolId, trancheId, price);
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
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, 0); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);

        evmInvestmentManager.deployTranche(poolId, trancheId);
        lPool = evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
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

    function toBytes29(bytes memory f) internal pure returns (bytes29 fc) {
        assembly {
            fc := mload(add(f, 29))
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
