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

interface IERC7540DepositReceiver {
    // inspired by https://eips.ethereum.org/EIPS/eip-721

    /// @notice Handle the receipt of an deposit Request
    /// @dev The ERC7540 smart contract calls this function on the recipient
    ///  after a `transfer`. This function MAY throw to revert and reject the
    ///  transfer. Return of other than the magic value MUST result in the
    ///  transaction being reverted.
    ///  Note: the contract address is always the message sender.
    /// @param _operator The address which called `safeTransferFrom` function
    /// @param _from The address which previously owned the deposit (or message sender)
    /// @param _ridId The RID identifier which is being transferred
    /// @param _data Additional data with no specified format
    /// @return `bytes4(keccak256("onERC7540DepositReceived(address,address,uint256,bytes)"))`
    ///  unless throwing
    function onERC7540DepositReceived(address _operator, address _from, uint256 _ridId, bytes calldata _data)
        external
        returns (bytes4);
}

interface IERC7540Deposit {
    event DepositRequest(address indexed sender, address indexed receiver, uint256 assets);

    /**
     * @dev Transfers assets from sender into the Vault and submits a Request for asynchronous deposit/mint.
     *
     * - MUST support ERC-20 approve / transferFrom on asset as a deposit Request flow.
     * - MUST revert if all of assets cannot be requested for deposit/mint.
     *
     * @param assets the amount of deposit assets from sender
     * @param receiver the receiver of the request who will be able to operate the request
     * @param sender the source of the deposit assets
     * @param data additional data which may be used to approve or call the receiver contract
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's underlying asset token.
     *
     * Behavior, if data is nonzero, attempt to call the receiver onERC7540DepositReceiver otherwise just send the
     * request to the receiver
     * sender MUST = msg.sender unless some unspecified explicit approval is given by the caller, approval of ERC7540
     * vault shares is NOT enough.
     */
    function requestDeposit(uint256 assets, address receiver, address sender, bytes calldata data)
        external
        returns (uint256 rid);

    /**
     * @dev Returns the amount of requested assets in Pending state for the operator to deposit or mint.
     *
     * - MUST NOT include any assets in Claimable state for deposit or mint.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingDepositRequest(uint256 rid) external view returns (uint256 assets);
}

interface IERC7540Redeem {
    event RedeemRequest(address indexed sender, address indexed operator, address indexed owner, uint256 shares);

    /**
     * @dev Assumes control of shares from owner and submits a Request for asynchronous redeem/withdraw.
     *
     * - MUST support a redeem Request flow where the control of shares is taken from owner directly
     *   where msg.sender has ERC-20 approval over the shares of owner.
     * - MUST revert if all of shares cannot be requested for redeem / withdraw.
     */
    function requestRedeem(uint256 shares, address operator, address owner) external;

    /**
     * @dev Returns the amount of requested shares in Pending state for the operator to redeem or withdraw.
     *
     * - MUST NOT include any shares in Claimable state for redeem or withdraw.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingRedeemRequest(address operator) external view returns (uint256 shares);
}

/**
 * @title  IERC7540
 * @dev    Interface of the ERC7540 "Asynchronous Tokenized Vault Standard", as defined in
 *         https://github.com/ethereum/EIPs/blob/2e63f2096b0c7d8388458bb0a03a7ce0eb3422a4/EIPS/eip-7540.md[ERC-7540].
 */
interface IERC7540 is IERC7540Deposit, IERC7540Redeem, IERC4626, IERC165 {
    /**
     * @dev returns the owner of a given request by requestId
     * Note: the rid MUST be unique for any given caller but not necessarily any given request. I.e. Rid may be an alias for `owner` OR it may uniquely identify a request. Contracts must be able to handle both cases.
     */
    function ownerOf(uint256 rid) external view returns (address owner);
}
