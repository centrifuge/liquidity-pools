// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IAggregatorV3} from "src/interfaces/factories/IAggregatorV3.sol";
import {Auth} from "src/Auth.sol";
import {IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";

contract VaultOracle is Auth, IAggregatorV3 {
    uint80 public constant ROUND_ID = 0;

    uint256 public immutable override version = 1;
    uint8 public immutable override decimals;

    IERC7540Vault public vault;

    // --- Events ---
    event File(bytes32 indexed what, address data);

    constructor(address vault_) Auth(msg.sender) {
        vault = IERC7540Vault(vault_);
        decimals = IERC20Metadata(vault.asset()).decimals();
    }

    // --- Administration ---
    function file(bytes32 what, address data) public auth {
        if (what == "vault") {
            require(
                address(vault) == address(0)
                    || (IERC7540Vault(data).share() == vault.share() && IERC7540Vault(data).asset() == vault.asset()),
                "VaultOracle/mismatching-asset-or-share"
            );
            vault = IERC7540Vault(data);
            emit File(what, data);
        } else {
            revert("VaultOracle/file-unrecognized-param");
        }
    }

    // --- Price computation ---
    function latestRoundData()
        public
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint256 priceLastUpdated = vault.priceLastUpdated();
        return (ROUND_ID, int256(vault.pricePerShare()), priceLastUpdated, priceLastUpdated, ROUND_ID);
    }

    function getRoundData(uint80 /* roundId */ )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return latestRoundData();
    }

    // --- View methods ---
    function description() external view returns (string memory) {
        string memory shareSymbol = IERC20Metadata(vault.share()).symbol();
        string memory assetSymbol = IERC20Metadata(vault.asset()).symbol();
        return string.concat(shareSymbol, " / ", assetSymbol);
    }
}
