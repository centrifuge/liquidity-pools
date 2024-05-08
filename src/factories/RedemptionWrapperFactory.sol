// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20, IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

contract RedemptionWrapper is ERC20 {
    IERC20 public immutable share;
    IERC20 public immutable asset;

    IERC7540 public vault;

    // --- Events ---
    event File(bytes32 indexed what, address data);

    constructor(address vault_) ERC20(IERC20Metadata(IERC7540(vault_).share()).decimals()) {
        vault = IERC7540(vault_);
        share = IERC20(vault.share());
        asset = IERC20(vault.asset());
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "vault") vault = IERC7540(data);
        else revert("RedemptionWrapper/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Interactions ---
    function mint(address to, uint256 value) public override {
        require(share.transferFrom(msg.sender, address(this), value), "RedemptionWrapper/failed-transfer");
        require(vault.requestRedeem(value, address(this), address(this), ""), "RedemptionWrapper/request-redeem-failed");

        super.mint(to, value);
    }

    function claim() public {
        vault.withdraw(vault.maxWithdraw(address(this)), address(this), address(this));
    }

    function burn(address from, uint256 value) public override {
        claim();
        require(asset.balanceOf(address(this)) >= value, "RedemptionWrapper/insufficient-asset-balance");

        super.burn(from, value);
        SafeTransferLib.safeTransferFrom(address(asset), address(this), msg.sender, value);
    }
}

/// @title  Redemption Wrapper Factory
/// @dev    Utility for deploying new redemption wrapper contracts
contract RedemptionWrapperFactory {
    address public immutable root;

    constructor(address _root) {
        root = _root;
    }

    function newVault(address vault) public returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(vault));

        RedemptionWrapper wrapper = new RedemptionWrapper{salt: salt}(vault);
        wrapper.rely(root);
        wrapper.deny(address(this));
        return address(wrapper);
    }
}
