// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import "./../../../util/Auth.sol";

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

interface AxelarExecutableLike {
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}

interface AxelarGatewayLike {
    function callContract(string calldata destinationChain, string calldata contractAddress, bytes calldata payload)
        external;
}

interface GatewayLike {
    function handle(bytes memory message) external;
}

contract AxelarEVMRouter is Auth, AxelarExecutableLike {
    AxelarGatewayLike public immutable axelarGateway;
    GatewayLike public gateway;

    string public constant axelarCentrifugeChainId = "Moonbeam";
    string public constant axelarCentrifugeChainAddress = "0x56c4Db5bEaD29FC19158aA1f85673D9865732be4";

    // --- Events ---
    event File(bytes32 indexed what, address addr);

    constructor(address axelarGateway_) {
        axelarGateway = AxelarGatewayLike(axelarGateway_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier onlyCentrifugeChainOrigin(string memory sourceChain) {
        require(
            msg.sender == address(axelarGateway)
                && keccak256(bytes(axelarCentrifugeChainId)) == keccak256(bytes(sourceChain)),
            "AxelarEVMRouter/invalid-origin"
        );
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "AxelarEVMRouter/only-gateway-allowed-to-call");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address gateway_) external auth {
        if (what == "gateway") {
            gateway = GatewayLike(gateway_);
        } else {
            revert("ConnectorXCMRouter/file-unrecognized-param");
        }

        emit File(what, gateway_);
    }

    // --- Incoming ---
    function execute(bytes32, string calldata sourceChain, string calldata, bytes calldata payload)
        external
        onlyCentrifugeChainOrigin(sourceChain)
    {
        gateway.handle(payload);
    }

    // --- Outgoing ---
    function send(bytes memory message) public onlyGateway {
        axelarGateway.callContract(axelarCentrifugeChainId, axelarCentrifugeChainAddress, message);
    }
}
