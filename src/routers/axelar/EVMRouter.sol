// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

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

contract AxelarEVMRouter is AxelarExecutableLike {
    mapping(address => uint256) public wards;

    InvestmentManagerLike public immutable investmentManager;
    AxelarGatewayLike public immutable axelarGateway;
    GatewayLike public gateway;

    string public constant axelarCentrifugeChainId = "Centrifuge";
    string public constant axelarCentrifugeChainAddress = "";

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address addr);

    constructor(address investmentManager_, address axelarGateway_) {
        investmentManager = InvestmentManagerLike(investmentManager_);
        axelarGateway = AxelarGatewayLike(axelarGateway_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "AxelarRouter/not-authorized");
        _;
    }

    modifier onlyCentrifugeChainOrigin(string memory sourceChain) {
        require(
            msg.sender == address(axelarGateway)
                && keccak256(bytes(axelarCentrifugeChainId)) == keccak256(bytes(sourceChain)),
            "AxelarRouter/invalid-origin"
        );
        _;
    }

    modifier onlyInvestmentManager() {
        require(msg.sender == address(investmentManager), "AxelarRouter/only-investmentManager-allowed-to-call");
        _;
    }

    // --- Administration ---
    function rely(address user) external auth {
        wards[user] = 1;
        emit Rely(user);
    }

    function deny(address user) external auth {
        wards[user] = 0;
        emit Deny(user);
    }

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
    function send(bytes memory message) public onlyInvestmentManager {
        axelarGateway.callContract(axelarCentrifugeChainId, axelarCentrifugeChainAddress, message);
    }
}
