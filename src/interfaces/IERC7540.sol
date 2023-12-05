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
    /**
     * @dev Handle the receipt of a deposit Request
     *
     * The ERC7540 smart contract calls this function on the recipient
     * after a `requestDeposit`. This function MAY throw to revert and reject the
     * request. Return of other than the magic value MUST result in the
     * transaction being reverted.
     * Inspired by https://eips.ethereum.org/EIPS/eip-721
     *
     * Note: the contract address is always the message sender.
     *
     * @param _operator The address which called `requestDeposit` function
     * @param _owner The address which funded the `assets` of the Request (or message sender)
     * @param _requestId The RID identifier of the Request which is being received
     * @param _data Additional data with no specified format
     * @return `bytes4(keccak256("onERC7540DepositReceived(address,address,uint256,bytes)"))`
     *  unless throwing
     */
    function onERC7540DepositReceived(address _operator, address _owner, uint256 _requestId, bytes memory _data)
        external
        returns (bytes4);
}

interface IERC7540RedeemReceiver {
    /**
     * @dev Handle the receipt of a redeem Request
     *
     * The ERC7540 smart contract calls this function on the recipient
     * after a `requestRedeem`. This function MAY throw to revert and reject the
     * request. Return of other than the magic value MUST result in the
     * transaction being reverted.
     * Inspired by https://eips.ethereum.org/EIPS/eip-721
     *
     * Note: the contract address is always the message sender.
     *
     * @param _operator The address which called `requestRedeem` function
     * @param _owner The address which funded the `shares` of the Request (or message sender)
     * @param _requestId The RID identifier of the Request which is being received
     * @param _data Additional data with no specified format
     * @return `bytes4(keccak256("onERC7540RedeemReceived(address,address,uint256,bytes)"))`
     *  unless throwing
     */
    function onERC7540RedeemReceived(address _operator, address _owner, uint256 _requestId, bytes memory _data)
        external
        returns (bytes4);
}

interface IERC7540Deposit {
    event DepositRequest(
        address indexed receiver, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );

    /**
     * @dev Transfers assets from sender into the Vault and submits a Request for asynchronous deposit.
     *
     * - MUST support ERC-20 approve / transferFrom on asset as a deposit Request flow.
     * - MUST revert if all of assets cannot be requested for deposit.
     * - owner MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from owner to sender is NOT enough.
     *
     * @param assets the amount of deposit assets to transfer from owner
     * @param receiver the receiver of the request who will be able to operate the request
     * @param owner the source of the deposit assets
     * @param data additional bytes which may be used to approve or call the receiver contract
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's underlying asset token.
     *
     * If data is nonzero, attempt to call the receiver onERC7540DepositReceived,
     * otherwise just send the request to the receiver
     */
    function requestDeposit(uint256 assets, address receiver, address owner, bytes calldata data)
        external
        returns (uint256 requestId);

    /**
     * @dev Returns the amount of requested assets in Pending state.
     *
     * - MUST NOT include any assets in Claimable state for deposit or mint.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingDepositRequest(uint256 requestId, address owner) external view returns (uint256 pendingAssets);

    /**
     * @dev Returns the amount of requested assets in Claimable state for the operator to deposit or mint.
     *
     * - MUST NOT include any assets in Pending state.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function claimableDepositRequest(uint256 requestId, address owner)
        external
        view
        returns (uint256 claimableAssets);
}

interface IERC7540Redeem {
    event RedeemRequest(
        address indexed receiver, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );

    /**
     * @dev Assumes control of shares from sender into the Vault and submits a Request for asynchronous redeem.
     *
     * - MUST support a redeem Request flow where the control of shares is taken from sender directly
     *   where msg.sender has ERC-20 approval over the shares of owner.
     * - MUST revert if all of shares cannot be requested for redeem.
     *
     * @param shares the amount of redemption shares to transfer from owner
     * @param receiver the receiver of the request who will be able to operate the request
     * @param owner the source of the redemption shares
     * @param data additional bytes which may be used to approve or call the receiver contract
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's share token.
     *
     * If data is nonzero, attempt to call the receiver onERC7540RedeemReceived,
     * otherwise just send the request to the receiver
     */
    function requestRedeem(uint256 shares, address receiver, address owner, bytes calldata data)
        external
        returns (uint256 requestId);

    /**
     * @dev Returns the amount of requested shares in Pending state.
     *
     * - MUST NOT include any shares in Claimable state for redeem or withdraw.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingRedeemRequest(uint256 requestId, address owner) external view returns (uint256 pendingShares);

    /**
     * @dev Returns the amount of requested shares in Claimable state for the operator to redeem or withdraw.
     *
     * - MUST NOT include any shares in Pending state for redeem or withdraw.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function claimableRedeemRequest(uint256 requestId, address owner) external view returns (uint256 claimableShares);
}

/**
 * @title  IERC7540
 * @dev    Interface of the ERC7540 "Asynchronous Tokenized Vault Standard", as defined in
 *         https://github.com/ethereum/EIPs/blob/2e63f2096b0c7d8388458bb0a03a7ce0eb3422a4/EIPS/eip-7540.md[ERC-7540].
 */
interface IERC7540 is IERC7540Deposit, IERC7540Redeem, IERC4626, IERC165 {}
