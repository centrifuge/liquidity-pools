// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {IERC4626} from "./IERC4626.sol";

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC7540Deposit {
    event DepositRequest(address indexed sender, address indexed receiver, address indexed owner, uint256 assets);

    /**
     * @dev Transfers assets from sender into the Vault and submits a Request for asynchronous deposit.
     *
     * - MUST support ERC-20 approve / transferFrom on asset as a deposit Request flow.
     * - MUST revert if all of assets cannot be requested for deposit.
     * - owner MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 shares from owner to sender is NOT enough.
     *
     * @param assets the amount of assets to transfer from owner
     * @param receiver the receiver of the request who will be able to operate the request
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's underlying asset token.
     */
    function requestDeposit(uint256 assets, address receiver) external;

    /**
     * @dev Returns the amount of requested assets in Pending state for the owner to deposit or mint.
     *
     * - MUST NOT include any assets in Claimable state for deposit or mint.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingDepositRequest(address owner) external view returns (uint256 assets);
}

interface IERC7540Redeem {
    event RedeemRequest(address indexed sender, address indexed receiver, address indexed owner, uint256 shares);

    /**
     * @dev Assumes control of shares from owner and submits a Request for asynchronous redeem.
     *
     * - MUST support a redeem Request flow where the control of shares is taken from owner directly
     *   where msg.sender has ERC-20 approval over the shares of owner.
     * - MUST revert if all of shares cannot be requested for redeem.
     *
     * @param shares the amount of shares to transfer from owner
     * @param receiver the receiver of the request who will be able to operate the request
     * @param owner the source of the shares
     */
    function requestRedeem(uint256 shares, address receiver, address owner) external;

    /**
     * @dev Returns the amount of requested shares in Pending state for the owner to redeem or withdraw.
     *
     * - MUST NOT include any shares in Claimable state for redeem or withdraw.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingRedeemRequest(address owner) external view returns (uint256 shares);
}

/**
 * @title  IERC7540
 * @dev    Interface of the ERC7540 "Asynchronous Tokenized Vault Standard", as defined in
 *         https://github.com/ethereum/EIPs/blob/2e63f2096b0c7d8388458bb0a03a7ce0eb3422a4/EIPS/eip-7540.md[ERC-7540].
 */
interface IERC7540 is IERC7540Deposit, IERC7540Redeem, IERC4626, IERC165 {}
