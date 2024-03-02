// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {BytesLib} from "./../libraries/BytesLib.sol";
import {Auth} from "./../Auth.sol";

interface ManagerLike {
    function handle(bytes memory message) external;
}

interface RouterAggregatorLike {
    function send(bytes memory message) external payable;
}

interface RootLike {
    function paused() external returns (bool);
    function scheduleRely(address target) external;
    function cancelRely(address target) external;
}

/// @title  Gateway
/// @dev    It parses incoming messages and forwards these to Managers
///         and it encoded outgoing messages and sends these to Routers.
///
///         If the Root is paused, any messages in and out of this contract
///         will not be forwarded
contract Gateway is Auth {
    using BytesLib for bytes;

    RootLike public immutable root;

    address public poolManager;
    RouterAggregatorLike public aggregator;
    address public investmentManager;

    uint256 public gasPriceOracle = 0.5 gwei;

    // --- Events ---
    event File(bytes32 indexed what, address data);

    constructor(address root_, address investmentManager_, address poolManager_) {
        root = RootLike(root_);
        investmentManager = investmentManager_;
        poolManager = poolManager_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier pauseable() {
        require(!root.paused(), "Gateway/paused");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) public auth {
        if (what == "poolManager") poolManager = data;
        else if (what == "aggregator") aggregator = RouterAggregatorLike(data);
        else if (what == "investmentManager") investmentManager = data;
        else revert("Gateway/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Outgoing ---
    // TODO: forward sender
    function send(bytes calldata message) public payable pauseable {
        // TODO: check by message ID, that the origin matches
        require(msg.sender == investmentManager || msg.sender == poolManager, "Gateway/invalid-manager");
        aggregator.send{value: msg.value}(message);
    }

    // --- Incoming ---
    function handle(bytes calldata message) external auth pauseable {
        (, address manager) = _parse(message);
        ManagerLike(manager).handle(message);
    }

    function _parse(bytes calldata message) internal view returns (uint8 id, address manager) {
        id = message.toUint8(0);

        // Hardcoded paths for pool & investment managers for gas efficiency
        // TODO: support root.schedule/cancelUpgrade
        if (id >= 1 && id <= 8) {
            manager = poolManager;
        } else if (id >= 9 && id <= 20) {
            manager = investmentManager;
        } else if (id >= 21 && id <= 26) {
            manager = poolManager;
        } else if (id == 27) {
            manager = investmentManager;
        } else {
            // TODO Dynamic path for other managers, to be able to easily
            // extend functionality of Liquidity Pools
            // address manager = managerByMessageId[id];
            // require(manager != address(0), "Gateway/unregistered-message-id");
            // return manager;
            manager = address(0);
        }
    }
}
