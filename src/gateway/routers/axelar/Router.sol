// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../../../util/Auth.sol";

interface InvestmentManagerLike {
    function addPool(uint64 poolId, uint128 currency, uint8 decimals) external;
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) external;
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) external;
    function handleTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        address destinationAddress,
        uint128 amount
    ) external;
}

interface AxelarGatewayLike {
    function callContract(string calldata destinationChain, string calldata contractAddress, bytes calldata payload)
        external;

    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool);
}

interface GatewayLike {
    function handle(bytes memory message) external;
}

contract AxelarRouter is Auth {
    string private constant axelarCentrifugeChainId = "Moonbeam";
    string private constant axelarCentrifugeChainAddress = "0x3b4a32efd7bd0290882B4854c86b8CECe534c975";

    AxelarGatewayLike public immutable axelarGateway;

    GatewayLike public gateway;

    // --- Events ---
    event File(bytes32 indexed what, address addr);

    constructor(address axelarGateway_) {
        axelarGateway = AxelarGatewayLike(axelarGateway_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier onlyCentrifugeChainOrigin(string calldata sourceChain) {
        require(msg.sender == address(axelarGateway), "AxelarRouter/invalid-origin");
        require(
            keccak256(bytes(axelarCentrifugeChainId)) == keccak256(bytes(sourceChain)),
            "AxelarRouter/invalid-source-chain"
        );
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "AxelarRouter/only-gateway-allowed-to-call");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") {
            gateway = GatewayLike(data);
        } else {
            revert("AxelarRouter/file-unrecognized-param");
        }

        emit File(what, data);
    }

    // --- Incoming ---
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) public onlyCentrifugeChainOrigin(sourceChain) {
        bytes32 payloadHash = keccak256(payload);
        require(
            axelarGateway.validateContractCall(commandId, sourceChain, sourceAddress, payloadHash),
            "Router/not-approved-by-gateway"
        );

        gateway.handle(payload);
    }

    // --- Outgoing ---
    function send(bytes calldata message) public onlyGateway {
        axelarGateway.callContract(axelarCentrifugeChainId, axelarCentrifugeChainAddress, message);
    }
}
