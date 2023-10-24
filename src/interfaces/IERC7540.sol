// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {IERC4626} from "./IERC4626.sol";

interface IERC165 {
    /// @notice Query if a contract implements an interface
    /// @param  interfaceId The interface identifier, as specified in ERC-165
    /// @dev    Interface identification is specified in ERC-165. This function
    ///         uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceId` and
    ///         `interfaceId` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}

interface IERC7540Deposit {
    event DepositRequest(address indexed sender, address indexed operator, uint256 assets);

    /**
     * @dev Transfers assets from msg.sender into the Vault and submits a Request for asynchronous deposit/mint.
     *
     * - MUST support ERC-20 approve / transferFrom on asset as a deposit Request flow.
     * - MUST revert if all of assets cannot be requested for deposit/mint.
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's underlying asset token.
     */
    function requestDeposit(uint256 assets, address operator) external;

    /**
     * @dev Returns the amount of requested assets in Pending state for the operator to deposit or mint.
     *
     * - MUST NOT include any assets in Claimable state for deposit or mint.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingDepositRequest(address operator) external view returns (uint256 assets);
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

/// @title  IERC7540
/// @dev    Interface of the ERC7540 "Asynchronous Tokenized Vault Standard", as defined in
///         https://github.com/ethereum/EIPs/blob/2e63f2096b0c7d8388458bb0a03a7ce0eb3422a4/EIPS/eip-7540.md[ERC-7540].
interface IERC7540 is IERC7540Deposit, IERC7540Redeem, IERC4626, IERC165 {}
