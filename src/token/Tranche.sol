// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "./ERC20.sol";
import {IERC20Metadata} from "../interfaces/IERC20.sol";

interface TrancheTokenLike is IERC20Metadata {
    function mint(address user, uint256 value) external;
    function burn(address user, uint256 value) external;
    function file(bytes32 what, string memory data) external;
    function file(bytes32 what, address data) external;
    function restrictionManager() external view returns (address);
    function addTrustedForwarder(address forwarder) external;
    function removeTrustedForwarder(address forwarder) external;
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
}

interface RestrictionManagerLike {
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
    function SUCCESS_CODE() external view returns (uint8);
    function afterTransfer(address from, address to, uint256 value) external;
    function afterMint(address to, uint256 value) external;
}

/// @title  Tranche Token
/// @notice Extension of ERC20 + ERC1404 for tranche tokens,
///         which manages the trusted forwarders for the ERC20 token, and ensures
///         the transfer restrictions as defined in the RestrictionManager.
contract TrancheToken is ERC20 {
    RestrictionManagerLike public restrictionManager;

    mapping(address => bool) public trustedForwarders;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event AddTrustedForwarder(address indexed trustedForwarder);
    event RemoveTrustedForwarder(address indexed trustedForwarder);

    constructor(uint8 decimals_) ERC20(decimals_) {}

    modifier restricted(address from, address to, uint256 value) {
        uint8 restrictionCode = detectTransferRestriction(from, to, value);
        require(restrictionCode == SUCCESS_CODE(), messageForTransferRestriction(restrictionCode));
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "restrictionManager") restrictionManager = RestrictionManagerLike(data);
        else revert("TrancheToken/file-unrecognized-param");
        emit File(what, data);
    }

    function addTrustedForwarder(address trustedForwarder) public auth {
        trustedForwarders[trustedForwarder] = true;
        emit AddTrustedForwarder(trustedForwarder);
    }

    function removeTrustedForwarder(address trustedForwarder) public auth {
        trustedForwarders[trustedForwarder] = false;
        emit RemoveTrustedForwarder(trustedForwarder);
    }

    // --- ERC20 overrides with restrictions ---
    function transfer(address to, uint256 value)
        public
        override
        restricted(_msgSender(), to, value)
        returns (bool success)
    {
        success = super.transfer(to, value);
        if (success) restrictionManager.afterTransfer(_msgSender(), to, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override
        restricted(from, to, value)
        returns (bool success)
    {
        success = super.transferFrom(from, to, value);
        if (success) restrictionManager.afterTransfer(from, to, value);
    }

    function mint(address to, uint256 value) public override restricted(_msgSender(), to, value) {
        super.mint(to, value);
        restrictionManager.afterMint(to, value);
    }

    // --- ERC1404 implementation ---
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        return restrictionManager.detectTransferRestriction(from, to, value);
    }

    function checkTransferRestriction(address from, address to, uint256 value) public view returns (bool) {
        return restrictionManager.detectTransferRestriction(from, to, value) == SUCCESS_CODE();
    }

    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string memory) {
        return restrictionManager.messageForTransferRestriction(restrictionCode);
    }

    function SUCCESS_CODE() public view returns (uint8) {
        return restrictionManager.SUCCESS_CODE();
    }

    // --- ERC2771Context ---
    /// @dev Trusted forwarders can forward custom msg.sender and
    ///      msg.data to the underlying ERC20 contract
    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return trustedForwarders[forwarder];
    }

    /// @dev Override for `msg.sender`. Defaults to the original `msg.sender` whenever
    ///      a call is not performed by the trusted forwarder or the calldata length is less than
    ///      20 bytes (an address length).
    function _msgSender() internal view virtual override returns (address sender) {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }
}
