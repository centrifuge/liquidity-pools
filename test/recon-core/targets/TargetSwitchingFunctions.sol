// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

// Recon Deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";

// @dev A way to change targets
// NOTE: There are many combinations
// NOTE: Using these functions helps you easily keep track of what's going on
abstract contract TargetSwitchingFunctions is BaseTargetFunctions, Properties {
    // Cycle through actors
    function changeActor(uint8 actorIndex) public {
        // Given actor swap to new actor
        // TODO
    }

    // // changePool
    // [pool][tranchesByCurrencies][INDEX] // changeTrancheForPool
    // [pool][tranchesByCurrencies][INDEX] // changeCurrencyForPool -> %= the Index

    // Cycle through Pools
    function changePool() public {
        // Given Pool, swap to new pool
        // Pool is easy
        // But given a Pool, we need to set a Tranche and a Currency
        // So we check if they exist, and use them

        // If they don't, we still switch
        // But we will need medusa to deploy a new Tranche (and currency)
    }

    // TODO: Consider adding ways to deploy
    // TODO: Check if it's worth having incorrect settings as a means to explore them

    // Cycle through Tranches -> Changes the Tranche ID without changing the currency
    function changeTrancheForPool() public {}

    // Changes the Currency being used
    // Keeps the Same Pool
    // Since it changes the currency, it also changes the tranche
    function changeCurrencyForPool() public {}
}
