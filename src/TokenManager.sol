// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.18;
// pragma abicoder v2;

// import {ERC20Like} from "./token/Restricted.sol";
// import "./auth/auth.sol";

// interface GatewayLike {
//     function transferTrancheTokensToCentrifuge(
//         uint64 poolId,
//         bytes16 trancheId,
//         address sender,
//         bytes32 destinationAddress,
//         uint128 amount
//     ) external;
//     function transferTrancheTokensToEVM(
//         uint64 poolId,
//         bytes16 trancheId,
//         address sender,
//         uint64 destinationChainId,
//         uint128 currencyId,
//         address destinationAddress,
//         uint128 amount
//     ) external;
//     function transfer(uint128 currency, address sender, bytes32 recipient, uint128 amount) external;
//     function paused() external returns (bool);
// }

// interface EscrowLike {
//     function approve(address token, address spender, uint256 value) external;
// }

// contract TokenManager is Auth {
//     GatewayLike public gateway;
//     EscrowLike public immutable escrow;

//     mapping(uint128 => address) public currencyIdToAddress; // chain agnostic currency id -> evm currency address
//     mapping(address => uint128) public currencyAddressToId; // The reverse mapping of `currencyIdToAddress`

//     // --- Events ---
//     event File(bytes32 indexed what, address data);

//     constructor(address escrow_) {
//         escrow = EscrowLike(escrow_);

//         wards[msg.sender] = 1;
//         emit Rely(msg.sender);
//     }

//     /// @dev checks whether gateway is active - can be used to prevent any interactions with centrifuge chain and stop all deposits & redemtions from escrow.
//     modifier gatewayActive() {
//         require(!gateway.paused(), "TokenManager/investmentManager-deactivated");
//         _;
//     }

//     /// @dev gateway must be message.sender. permissions check for incoming message handling.
//     modifier onlyGateway() {
//         require(msg.sender == address(gateway), "TokenManager/not-the-gateway");
//         _;
//     }

//     // --- Administration ---
//     function file(bytes32 what, address data) external auth {
//         if (what == "gateway") gateway = GatewayLike(data);
//         else revert("TokenManager/file-unrecognized-param");
//         emit File(what, data);
//     }

//     // --- public outgoing message handling ---
//     function transfer(address currencyAddress, bytes32 recipient, uint128 amount) public {
//         uint128 currency = currencyAddressToId[currencyAddress];
//         require(currency != 0, "TokenManager/unknown-currency");

//         ERC20Like erc20 = ERC20Like(currencyAddress);
//         require(erc20.balanceOf(msg.sender) >= amount, "TokenManager/insufficient-balance");
//         require(erc20.transferFrom(msg.sender, address(escrow), amount), "TokenManager/currency-transfer-failed");

//         gateway.transfer(currency, msg.sender, recipient, amount);
//     }

//     function transferTrancheTokensToCentrifuge(
//         uint64 poolId,
//         bytes16 trancheId,
//         address currency, // we need this as there is liquidityPool per supported currency
//         bytes32 destinationAddress,
//         uint128 amount
//     ) public {
//         ERC20Like lPool = ERC20Like(liquidityPools[poolId][trancheId][currency]);
//         require(address(lPool) != address(0), "TokenManager/unknown-token");

//         require(lPool.balanceOf(msg.sender) >= amount, "TokenManager/insufficient-balance");
//         lPool.burn(msg.sender, amount);

//         gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, msg.sender, destinationAddress, amount);
//     }

//     function transferTrancheTokensToEVM(
//         uint64 poolId,
//         bytes16 trancheId,
//         address currency,
//         uint64 destinationChainId,
//         address destinationAddress,
//         uint128 amount
//     ) public {
//         ERC20Like lPool = ERC20Like(liquidityPools[poolId][trancheId][currency]);
//         require(address(lPool) != address(0), "TokenManager/unknown-token");

//         require(lPool.balanceOf(msg.sender) >= amount, "TokenManager/insufficient-balance");
//         lPool.burn(msg.sender, amount);

//         uint128 currencyId = currencyAddressToId[currency];
//         require(currencyId != 0, "TokenManager/unknown-currency");

//         gateway.transferTrancheTokensToEVM(
//             poolId, trancheId, msg.sender, destinationChainId, currencyId, destinationAddress, amount
//         );
//     }

//     // --- Incoming message handling ---
//     function handleTransfer(uint128 currency, address recipient, uint128 amount) public onlyGateway {
//         address currencyAddress = currencyIdToAddress[currency];
//         require(currencyAddress != address(0), "TokenManager/unknown-currency");

//         EscrowLike(escrow).approve(currencyAddress, address(this), amount);
//         require(
//             ERC20Like(currencyAddress).transferFrom(address(escrow), recipient, amount),
//             "TokenManager/currency-transfer-failed"
//         );
//     }

// }
