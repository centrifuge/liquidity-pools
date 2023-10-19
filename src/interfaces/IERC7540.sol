// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {IERC4626} from "./IERC4626.sol";

/// @title  IERC7540
/// @dev    Interface of the ERC7540 "Asynchronous Tokenized Vault Standard", as defined in
///         https://github.com/ethereum/EIPs/blob/2e63f2096b0c7d8388458bb0a03a7ce0eb3422a4/EIPS/eip-7540.md[ERC-7540].
interface IERC7540 is IERC4626 {
    event DepositRequest(address indexed sender, address indexed operator, uint256 assets);
    event RedeemRequest(address indexed sender, address indexed operator, address indexed owner, uint256 shares);

    /**
     * @dev Transfers assets from msg.sender into the Vault and submits a Request for asynchronous deposit/mint.
     *      This places the Request in Pending state, with a corresponding increase in pendingDepositRequest for the
     * amount assets.
     */
    function requestDeposit(uint256 assets, address operator) external;

    /**
     * @dev Returns the amount of requested assets in Pending state for the operator to deposit or mint.
     */
    function pendingDepositRequest(address operator) external view returns (uint256 assets);

    /**
     * @dev Assumes control of shares from owner and submits a Request for asynchronous redeem/withdraw.
     *      This places the Request in Pending state, with a corresponding increase in pendingRedeemRequest for the
     * amount shares.
     */
    function requestRedeem(uint256 shares, address operator, address owner) external;

    /**
     * @dev Returns the amount of requested shares in Pending state for the operator to redeem or withdraw.
     */
    function pendingRedeemRequest(address operator) external view returns (uint256 shares);
}
