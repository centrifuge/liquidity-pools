// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import { CentrifugeConnector, Tranche } from "../src/Connector.sol";
import { ConnectorGateway } from "../src/routers/Gateway.sol";
import { ConnectorEscrow } from "../src/Escrow.sol";
import { LiquidityPoolFactory, MemberlistFactory } from "../src/liquidityPool/Factory.sol";
import { LiquidityPool } from "../src/liquidityPool/LiquidityPool.sol";
import { ERC20 } from "../src/token/erc20.sol";

import { MemberlistLike, Memberlist } from "../src/token/memberlist.sol";
import { MockHomeConnector } from "./mock/MockHomeConnector.sol";
import { MockXcmRouter } from "./mock/MockXcmRouter.sol";
import { ConnectorMessages } from "../src/Messages.sol";
import { ConnectorPauseAdmin } from "../src/admin/PauseAdmin.sol";
import { ConnectorDelayedAdmin } from "../src/admin/DelayedAdmin.sol";
import "forge-std/Test.sol";
import "../src/Connector.sol";

interface EscrowLike_ {
    function approve(address token, address spender, uint256 value) external;
    function rely(address usr) external;
}

interface AuthLike {
    function wards(address user) external returns (uint);
}

contract ConnectorTest is Test {
    CentrifugeConnector evmConnector;
    ConnectorGateway gateway;
    MockHomeConnector connector;
    MockXcmRouter mockXcmRouter;

    function setUp() public {
        vm.chainId(1);
        uint256 shortWait = 24 hours;
        uint256 longWait = 48 hours;
        uint256 gracePeriod = 48 hours;
        address escrow_ = address(new ConnectorEscrow());
        address liquidityPoolFactory_ = address(new LiquidityPoolFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        evmConnector = new CentrifugeConnector(escrow_, liquidityPoolFactory_, memberlistFactory_);

        mockXcmRouter = new MockXcmRouter(address(evmConnector));

        connector = new MockHomeConnector(address(mockXcmRouter));
        ConnectorPauseAdmin pauseAdmin = new ConnectorPauseAdmin();
        ConnectorDelayedAdmin delayedAdmin = new ConnectorDelayedAdmin();

        gateway =
            new ConnectorGateway(address(evmConnector), address(mockXcmRouter), shortWait, longWait, gracePeriod);
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        evmConnector.file("gateway", address(gateway));
        EscrowLike_(escrow_).rely(address(evmConnector));
        mockXcmRouter.file("gateway", address(gateway));
        evmConnector.rely(address(gateway));
        ConnectorEscrow(escrow_).rely(address(gateway));
    }

    // function testConnectorDeactivationWorks() public {
    //     gateway.pause();
    //     vm.expectRevert(bytes("CentrifugeConnector/connector-deactivated"));
    //     evmConnector.processDeposit(address(0), address(0), 0);
    // } 


    function testAddCurrencyWorks(uint128 currency, uint128 badCurrency) public {
        vm.assume(currency > 0);
        vm.assume(badCurrency > 0);
        vm.assume(currency != badCurrency);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addCurrency(currency, address(erc20));
        (address address_) =  evmConnector.currencyIdToAddress(currency);
        assertEq(address_, address(erc20));

        // Verify we can't override the same currency id another address
        ERC20 badErc20 = newErc20("BadActor's Dollar", "BADUSD", 66);
        vm.expectRevert(bytes("CentrifugeConnector/currency-id-in-use"));
        connector.addCurrency(currency, address(badErc20));
        assertEq( evmConnector.currencyIdToAddress(currency), address(erc20));

        // Verify we can't add a currency address that already exists associated with a different currency id
        vm.expectRevert(bytes("CentrifugeConnector/currency-address-in-use"));
        connector.addCurrency(badCurrency, address(erc20));
        assertEq( evmConnector.currencyIdToAddress(currency), address(erc20));
    }

    function testAddPoolWorks(uint64 poolId) public {
        connector.addPool(poolId);
        (uint64 actualPoolId,,) = evmConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
    }

    function testAllowPoolCurrencyWorks(uint128 currency, uint64 poolId) public {
        vm.assume(currency > 0);
        ERC20 token = newErc20("X's Dollar", "USDX", 42);
        connector.addCurrency(currency, address(token));
        connector.addPool(poolId);

        connector.allowPoolCurrency(poolId, currency);
        assertTrue(evmConnector.allowedPoolCurrencies(poolId, address(token)));
    }

    function testAllowPoolCurrencyWithUnknownCurrencyFails(uint128 currency, uint64 poolId) public {
        connector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/unknown-currency"));
        connector.allowPoolCurrency(poolId, currency);
    }

    function testAddingPoolMultipleTimesFails(uint64 poolId) public {
        connector.addPool(poolId);

        vm.expectRevert(bytes("CentrifugeConnector/pool-already-added"));
        connector.addPool(poolId);
    }

    function testAddingPoolAsNonRouterFails(uint64 poolId) public {
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        evmConnector.addPool(poolId);
    }

    function testAddingSingleTrancheWorks(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        connector.addPool(poolId);
        (uint64 actualPoolId,,) = evmConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);

        (
            uint64 poolId_,
            bytes16 trancheId_,
            uint256 createdAt_,
            string memory tokenName_,
            string memory tokenSymbol_,
            uint8 decimals_
        ) = evmConnector.tranches(poolId, trancheId);

        address[] memory liquidityPools_ = evmConnector.getLiquidityPoolsForTranche(poolId, trancheId);

        assertEq(poolId, poolId_);
        assertEq(trancheId, trancheId_);
        assertEq(block.timestamp, createdAt_);
        assertEq( bytes32ToString(stringToBytes32(tokenName)), bytes32ToString(stringToBytes32(tokenName_)));
        assertEq( bytes32ToString(stringToBytes32(tokenSymbol)), bytes32ToString(stringToBytes32(tokenSymbol_)));
        assertEq(decimals, decimals_);
        assertEq(liquidityPools_.length, 0);  
    }

    function testAddingTrancheMultipleTimesFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);

        vm.expectRevert(bytes("CentrifugeConnector/tranche-already-exists"));
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testAddingMultipleTranchesWorks(
        uint64 poolId,
        bytes16[] calldata trancheIds,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        vm.assume(trancheIds.length > 0 && trancheIds.length < 5);
        vm.assume(!hasDuplicates(trancheIds));
        connector.addPool(poolId);

        for (uint256 i = 0; i < trancheIds.length; i++) {
            connector.addTranche(poolId, trancheIds[i], tokenName, tokenSymbol, decimals, price);
            (
                uint64 poolId_,
                bytes16 trancheId_,,,,
            ) = evmConnector.tranches(poolId, trancheIds[i]);

            assertEq(poolId, poolId_);
            assertEq(trancheIds[i], trancheId_);
        }
    }

    function testAddingTranchesAsNonRouterFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        connector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        evmConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testAddingTranchesForNonExistentPoolFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool"));
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testDeployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public { 
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);
       
        address lPoolAddress = evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20)); 
        address lPool_ = evmConnector.liquidityPools(poolId, trancheId, address(erc20)); // make sure the pool was stored in connectors 
        address[] memory liquidityPools = evmConnector.getLiquidityPoolsForTranche(poolId, trancheId);

        // make sure the pool was added to the tranche struct
        assertEq(lPoolAddress, lPool_);
        bool lPoolIncluded;
        for (uint i=0; i<liquidityPools.length; i++) {
            if (liquidityPools[i] == lPool_) {
                lPoolIncluded = true;
            }
        }
        assertTrue(lPoolIncluded == true);

        // check LiquidityPool state
        LiquidityPool lPool = LiquidityPool(lPool_);
        assertEq(address(lPool.connector()), address(evmConnector));
        assertEq(lPool.asset(), address(erc20));
        assertEq(lPool.poolId(), poolId);
        assertEq(lPool.trancheId(), trancheId);

        assertEq(lPool.name(), bytes32ToString(stringToBytes32(tokenName)));
        assertEq(lPool.symbol(), bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(lPool.decimals(), decimals);

        // check wards
        assertTrue(lPool.hasMember(address(evmConnector.escrow())));
        assertTrue(lPool.wards(address(gateway)) == 1);
        assertTrue(lPool.wards(address(evmConnector)) == 1);
        assertTrue(lPool.wards(address(this)) == 0);
        assertTrue(evmConnector.liquidityPoolWards(lPoolAddress) == 1);
    }

    function testDeployingLiquidityPoolNonExistingTrancheFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        bytes16 wrongTrancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        vm.assume(trancheId != wrongTrancheId);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);
        vm.expectRevert(bytes("CentrifugeConnector/tranche-does-not-exist"));
        evmConnector.deployLiquidityPool(poolId, wrongTrancheId, address(erc20));
    }

    function testDeployingLiquidityPoolNonExistingPoolFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint64  wrongPoolId,
        uint128 price,
        uint128 currency
      ) public {
        vm.assume(currency > 0);
        vm.assume(poolId != wrongPoolId);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);
        vm.expectRevert(bytes("CentrifugeConnector/pool-does-not-exist"));
        evmConnector.deployLiquidityPool(wrongPoolId, trancheId, address(erc20));
    }

    function testDeployingLiquidityPoolCurrencyNotSupportedFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
     ) public {
        vm.assume(currency > 0);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        
        connector.addCurrency(currency, address(erc20));
        
        vm.expectRevert(bytes("CentrifugeConnector/pool-currency-not-allowed"));
        evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20));
    }

    function testDeployLiquidityPoolTwiceFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public { 
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);
       
        evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20)); 
        vm.expectRevert(bytes("CentrifugeConnector/liquidityPool-already-deployed"));
        evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20)); 
        
    }

    function testUpdatingMemberWorks(uint64 poolId, uint8 decimals, uint128 currency, string memory tokenName, string memory tokenSymbol, bytes16 trancheId, address user, uint64 validUntil, uint128 price)
        public
    {
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);
        address lPool_ = evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20)); 

        connector.updateMember(poolId, trancheId, user, validUntil);
        assertTrue(LiquidityPool(lPool_).hasMember(user));
    }
 
    function testUpdatingMemberAsNonRouterFails(uint64 poolId, uint128 currency, bytes16 trancheId, address user, uint64 validUntil)
        public
    {
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));
        vm.assume(currency > 0);

        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        evmConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentPoolFails(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp);
        evmConnector.file("gateway", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        evmConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp);
        connector.addPool(poolId);

        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        connector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingTokenPriceWorks(uint64 poolId, uint8 decimals, uint128 currency, string memory tokenName, string memory tokenSymbol, bytes16 trancheId, uint128 price) public {
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);
        address lPool_ = evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20)); 
       
        connector.updateTokenPrice(poolId, trancheId, price);
        assertEq(LiquidityPool(lPool_).latestPrice(), price);
        assertEq(LiquidityPool(lPool_).lastPriceUpdate(), block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(uint64 poolId, uint8 decimals, uint128 currency, string memory tokenName, string memory tokenSymbol, bytes16 trancheId, uint128 price) public {
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);
        evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20)); 
        
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        evmConnector.updateTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        evmConnector.file("gateway", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        evmConnector.updateTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        connector.addPool(poolId);

        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        connector.updateTokenPrice(poolId, trancheId, price);
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
        connector.addCurrency(currency, address(erc20));

        assertEq(erc20.balanceOf(address(evmConnector.escrow())), 0);
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        connector.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmConnector.escrow())), 0);
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
        connector.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(evmConnector), type(uint256).max);
        erc20.mint(address(this), amount);
        evmConnector.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmConnector.escrow())), amount);

        // Now we test the incoming message
        connector.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmConnector.escrow())), 0);
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

        vm.expectRevert(bytes("CentrifugeConnector/unknown-currency"));
        evmConnector.transfer(address(erc20), recipient, amount);
        connector.addCurrency(currency, address(erc20));

        erc20.mint(address(this), initialBalance);
        assertEq(erc20.balanceOf(address(this)), initialBalance);
        assertEq(erc20.balanceOf(address(evmConnector.escrow())), 0);
        erc20.approve(address(evmConnector), type(uint256).max);

        evmConnector.transfer(address(erc20), recipient, amount);
        assertEq(erc20.balanceOf(address(this)), initialBalance - amount);
        assertEq(erc20.balanceOf(address(evmConnector.escrow())), amount);
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
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        // fund this account with amount
        connector.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), currency, address(this), amount);

        // Verify the address(this) has the expected amount
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), amount);

        // Now send the transfer from EVM -> Cent Chain
        LiquidityPool(lPool_).approve(address(evmConnector), amount);
        evmConnector.transferTrancheTokensToCentrifuge(poolId, trancheId, LiquidityPool(lPool_).asset(), centChainAddress, amount);
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), 0);

        // Finally, verify the connector called `router.send`
        bytes memory message = ConnectorMessages.formatTransferTrancheTokens(
            poolId,
            trancheId,
            bytes32(bytes20(address(this))),
            ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge),
            currency,
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
       
        connector.updateMember(poolId, trancheId, destinationAddress, validUntil);
        assertTrue(LiquidityPool(lPool_).hasMember(destinationAddress));
        connector.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), currency, destinationAddress, amount);
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

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        connector.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), currency, destinationAddress, amount);
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
        connector.updateMember(poolId, trancheId, destinationAddress, validUntil);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        // Fund this address with amount
        connector.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), currency, address(this), amount);
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), amount);

        // Approve and transfer amount from this address to destinationAddress
        LiquidityPool(lPool_).approve(address(evmConnector), amount);
        evmConnector.transferTrancheTokensToEVM(
            poolId, trancheId, LiquidityPool(lPool_).asset(), uint64(block.chainid), destinationAddress, amount
        );
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), 0);
    }

    
    function testCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        uint8 trancheDecimals,
        uint64 validUntil,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(currency > 0);
        vm.assume(trancheDecimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, 0); // add tranche
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-tranche-token"));
        evmConnector.collectRedeem(poolId, trancheId, address(erc20));

        address lPool_ = evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20)); 
        
        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        evmConnector.collectRedeem(poolId, trancheId, LiquidityPool(lPool_).asset());
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        evmConnector.collectRedeem(poolId, trancheId, LiquidityPool(lPool_).asset());
    }

    function testCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        uint64 validUntil,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(currency > 0);
        vm.assume(decimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, 0); // add tranche
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-tranche-token"));
        evmConnector.collectInvest(poolId, trancheId, address(erc20));

        address lPool_ = evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        evmConnector.collectInvest(poolId, trancheId, LiquidityPool(lPool_).asset());
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        evmConnector.collectInvest(poolId, trancheId, LiquidityPool(lPool_).asset());
    }

    // helpers
    function deployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency) internal returns (address lPool) {
        // deploy liquidityPool
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addPool(poolId); // add pool 
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, 0); // add tranche
        connector.addCurrency(currency, address(erc20));
        connector.allowPoolCurrency(poolId, currency);
    
        lPool = evmConnector.deployLiquidityPool(poolId, trancheId, address(erc20)); 
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