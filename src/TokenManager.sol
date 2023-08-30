// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenLike} from "./token/Tranche.sol";
import {MemberlistLike} from "./token/Memberlist.sol";
import "./token/IERC20.sol";
import "./util/Auth.sol";

interface GatewayLike {
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        bytes32 destinationAddress,
        uint128 amount
    ) external;
    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) external;
    function transfer(uint128 currency, address sender, bytes32 recipient, uint128 amount) external;
}

interface InvestmentManagerLike {
    function liquidityPools(uint64 poolId, bytes16 trancheId, address currency) external returns (address);
    function getTrancheToken(uint64 _poolId, bytes16 _trancheId) external view returns (address);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

contract TokenManager is Auth {
    GatewayLike public gateway;
    InvestmentManagerLike public investmentManager;
    EscrowLike public immutable escrow;

    mapping(uint128 => address) public currencyIdToAddress; // chain agnostic currency id -> evm currency address
    mapping(address => uint128) public currencyAddressToId; // The reverse mapping of `currencyIdToAddress`

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event CurrencyAdded(uint128 indexed currency, address indexed currencyAddress);

    constructor(address escrow_) {
        escrow = EscrowLike(escrow_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev gateway must be message.sender. permissions check for incoming message handling.
    modifier onlyGateway() {
        require(msg.sender == address(gateway), "TokenManager/not-the-gateway");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
        else if (what == "investmentManager") investmentManager = InvestmentManagerLike(data);
        else revert("TokenManager/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Outgoing message handling ---
    function transfer(address currencyAddress, bytes32 recipient, uint128 amount) public {
        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "TokenManager/unknown-currency");

        ERC20Like erc20 = ERC20Like(currencyAddress);
        require(erc20.balanceOf(msg.sender) >= amount, "TokenManager/insufficient-balance");
        require(erc20.transferFrom(msg.sender, address(escrow), amount), "TokenManager/currency-transfer-failed");

        gateway.transfer(currency, msg.sender, recipient, amount);
    }

    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 destinationAddress,
        uint128 amount
    ) public {
        TrancheTokenLike trancheToken = TrancheTokenLike(investmentManager.getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "TokenManager/unknown-token");

        require(trancheToken.balanceOf(msg.sender) >= amount, "TokenManager/insufficient-balance");
        trancheToken.burn(msg.sender, amount);

        gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, msg.sender, destinationAddress, amount);
    }

    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        TrancheTokenLike trancheToken = TrancheTokenLike(investmentManager.getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "TokenManager/unknown-token");

        require(trancheToken.balanceOf(msg.sender) >= amount, "TokenManager/insufficient-balance");
        trancheToken.burn(msg.sender, amount);

        gateway.transferTrancheTokensToEVM(
            poolId, trancheId, msg.sender, destinationChainId, destinationAddress, amount
        );
    }

    // --- Incoming message handling ---
    function updateTrancheTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) public onlyGateway {
        TrancheTokenLike trancheToken = TrancheTokenLike(investmentManager.getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "TokenManager/unknown-token");

        trancheToken.updatePrice(price);
    }

    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public onlyGateway {
        TrancheTokenLike trancheToken = TrancheTokenLike(investmentManager.getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "TokenManager/unknown-token");

        trancheToken.file("name", tokenName);
        trancheToken.file("symbol", tokenSymbol);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public onlyGateway {
        TrancheTokenLike trancheToken = TrancheTokenLike(investmentManager.getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "TokenManager/unknown-token");

        MemberlistLike memberlist = MemberlistLike(trancheToken.memberlist());
        memberlist.updateMember(user, validUntil);
    }

    /// @dev a global chain agnostic currency index is maintained on centrifuge chain. This function maps a currency from the centrifuge chain index to its corresponding address on the evm chain.
    /// The chain agnostic currency id has to be used to pass currency information to the centrifuge chain.
    /// @notice this function can only be executed by the gateway contract.
    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        // currency index on the centrifuge chain side should start at 1
        require(currency > 0, "TokenManager/currency-id-has-to-be-greater-than-0");
        require(currencyIdToAddress[currency] == address(0), "TokenManager/currency-id-in-use");
        require(currencyAddressToId[currencyAddress] == 0, "TokenManager/currency-address-in-use");

        currencyIdToAddress[currency] = currencyAddress;
        currencyAddressToId[currencyAddress] = currency;

        // enable taking the currency out of escrow in case of redemptions
        EscrowLike(escrow).approve(currencyAddress, address(investmentManager), type(uint256).max);
        EscrowLike(escrow).approve(currencyAddress, address(this), type(uint256).max);
        emit CurrencyAdded(currency, currencyAddress);
    }

    function handleTransfer(uint128 currency, address recipient, uint128 amount) public onlyGateway {
        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "TokenManager/unknown-currency");

        EscrowLike(escrow).approve(currencyAddress, address(this), amount);
        require(
            ERC20Like(currencyAddress).transferFrom(address(escrow), recipient, amount),
            "TokenManager/currency-transfer-failed"
        );
    }

    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        public
        onlyGateway
    {
        TrancheTokenLike trancheToken = TrancheTokenLike(investmentManager.getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "TokenManager/unknown-token");

        require(trancheToken.hasMember(destinationAddress), "TokenManager/not-a-member");
        trancheToken.mint(destinationAddress, amount);
    }
}
