// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {BytesLib} from "./../libraries/BytesLib.sol";
import {Auth} from "./../Auth.sol";
import {IGateway} from "src/interfaces/gateway/IGateway.sol";

interface ManagerLike {
    function handle(bytes memory message) external;
}

interface AggregatorLike {
    function send(bytes memory message) external;
}

interface RootLike {
    function paused() external returns (bool);
    function scheduleRely(address target) external;
    function cancelRely(address target) external;
    function recoverTokens(address target, address token, address to, uint256 amount) external;
}

/// @title  Gateway
/// @dev    It parses incoming messages and forwards these to Managers
///         and it encoded outgoing messages and sends these to Routers.
///
///         If the Root is paused, any messages in and out of this contract
///         will not be forwarded
contract Gateway is Auth, IGateway {
    using BytesLib for bytes;

    RootLike public immutable root;

    address public poolManager;
    address public investmentManager;
    AggregatorLike public aggregator;

    mapping(uint8 messageId => address manager) messages;

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
        else if (what == "aggregator") aggregator = AggregatorLike(data);
        else if (what == "investmentManager") investmentManager = data;
        else revert("Gateway/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, uint8 data1, address data2) public auth {
        if (what == "message") messages[data1] = data2;
        else revert("Gateway/file-unrecognized-param");
        emit File(what, data1, data2);
    }

    // --- Outgoing ---
    function send(bytes calldata message) public pauseable {
        require(
            msg.sender == investmentManager || msg.sender == poolManager || msg.sender == messages[message.toUint8(0)],
            "Gateway/invalid-manager"
        );
        aggregator.send(message);
    }

    // --- Incoming ---
    function handle(bytes calldata message) external auth pauseable {
        _handle(message);
    }

    function _handle(bytes calldata message) internal {
        uint8 id = message.toUint8(0);
        address manager;

        // Hardcoded paths for root + pool & investment managers for gas efficiency
        if (id >= 1 && id <= 8 || id >= 23 && id <= 26) {
            manager = poolManager;
        } else if (id >= 9 && id <= 20 || id == 27) {
            manager = investmentManager;
        } else if (id >= 21 && id <= 22 || id == 31) {
            manager = address(root);
        } else if (id == 32) {
            // Handle batch messages
            uint256 start = 1;
            while (start < message.length) {
                uint16 length = message.toUint16(start);
                _handle(message[start + 2:start + 2 + length]);
                start += 2 + length;
            }
            return;
        } else {
            // Dynamic path for other managers, to be able to easily
            // extend functionality of Liquidity Pools
            manager = messages[id];
            require(manager != address(0), "Gateway/unregistered-message-id");
        }

        ManagerLike(manager).handle(message);
    }
}
