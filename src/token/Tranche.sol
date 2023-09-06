// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "./ERC20.sol";
import {IERC20} from "../interfaces/IERC20.sol";

interface TrancheTokenLike is IERC20 {
    function hasMember(address user) external view returns (bool);
    function updatePrice(uint128 price) external;
    function memberlist() external returns (address);
    function file(bytes32 what, string memory data) external;
}

interface ERC1404Like is ERC20 {
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8);
    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string);
    function SUCCESS_CODE() public view returns (uint8);
}

contract TrancheToken is ERC20, ERC1404Like {
    ERC1404Like public restrictionManager;

    mapping(address => bool) public liquidityPools;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event AddLiquidityPool(address indexed liquidityPool);
    event RemoveLiquidityPool(address indexed liquidityPool);

    constructor(uint8 decimals_) ERC20(decimals_) {}

    modifier notRestricted(address from, address to, address value) {
        uint8 restrictionCode = detectTransferRestriction(from, to, value);
        require(restrictionCode == restrictionManager.SUCCESS_CODE(), messageForTransferRestriction(restrictionCode));
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) public auth {
        if (what == "restrictionManager") restrictionManager = ERC1404Like(data);
        else revert("TrancheToken/file-unrecognized-param");
        emit File(what, data);
    }

    function addLiquidityPool(address liquidityPool) public auth {
        liquidityPools[liquidityPool] = true;
        emit AddLiquidityPool(liquidityPool);
    }

    function removeLiquidityPool(address liquidityPool) public auth {
        liquidityPools[liquidityPool] = false;
        emit RemoveLiquidityPool(liquidityPool);
    }

    // --- Restrictions ---
    function transfer(address to, uint256 value) public override notRestricted(msg.sender, to, value) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override
        notRestricted(from, to, value)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    function mint(address to, uint256 value) public override notRestricted(msg.sender, to, value) {
        return super.mint(to, value);
    }

    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        return restrictionManager.detectTransferRestriction(from, to, value);
    }

    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string) {
        return restrictionManager.messageForTransferRestriction(restrictionCode);
    }

    // --- ERC2771Context ---
    function isTrustedForwarder(address forwarder) public view returns (bool) {
        // Liquidity Pools are considered trusted forwarders
        // for the ERC2771Context implementation of the underlying
        // ERC20 token
        return liquidityPools[forwarder];
    }

    /**
     * @dev Override for `msg.sender`. Defaults to the original `msg.sender` whenever
     * a call is not performed by the trusted forwarder or the calldata length is less than
     * 20 bytes (an address length).
     */
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
