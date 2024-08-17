// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Metadata, IERC20Wrapper} from "src/interfaces/IERC20.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

contract ClaimToken is ERC20 {
    IERC20Metadata public immutable share;

    // --- Events ---
    event File(bytes32 indexed what, address data);

    constructor(address share_) ERC20(IERC20Metadata(share_).decimals()) {
        share = IERC20Metadata(share_);
    }

    // --- Metadata overrides ---
    /// @dev Sets name to [Share Name] Claim
    function name() external view override returns (string memory) {
        return string.concat(share.name(), " Claim");
    }

    /// @dev Sets symbol to c[SHARE_SYMBOL]
    function symbol() external view override returns (string memory) {
        return string.concat("c", share.symbol());
    }
}

contract RedemptionWrapper is ERC20, IERC20Wrapper {
    IERC20Metadata public immutable share;
    IERC20Metadata public immutable asset;
    ERC20 public immutable claimToken;
    address public immutable user;

    IERC7540 public vault;

    // --- Events ---
    event File(bytes32 indexed what, address data);

    constructor(address vault_, address claimToken_, address user_)
        ERC20(IERC20Metadata(IERC7540(vault_).share()).decimals())
    {
        vault = IERC7540(vault_);
        share = IERC20Metadata(vault.share());
        asset = IERC20Metadata(vault.asset());
        claimToken = ERC20(claimToken_);
        user = user_;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "vault") vault = IERC7540(data);
        else revert("RedemptionWrapper/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Interactions ---
    function depositFor(address account, uint256 value) external returns (bool) {
        require(msg.sender == user, "RedemptionWrapper/invalid-user");
        require(share.transferFrom(msg.sender, address(this), value), "RedemptionWrapper/failed-transfer");
        vault.requestRedeem(value, address(this), address(this), "");

        claimToken.mint(account, value);

        return true;
    }

    function claim() public {
        vault.withdraw(vault.maxWithdraw(address(this)), address(this), address(this));
    }

    function withdrawTo(address account, uint256 value) external returns (bool) {
        claim();
        claimToken.burn(msg.sender, value);
        require(asset.balanceOf(address(this)) >= value, "RedemptionWrapper/insufficient-asset-balance");
        SafeTransferLib.safeTransferFrom(address(asset), address(this), msg.sender, value);
    }
}

/// @title  Redemption Wrapper Factory
/// @dev    Utility for deploying new redemption wrapper contracts
contract RedemptionWrapperFactory {
    address public immutable root;

    mapping(address share => ERC20) claimToken;

    constructor(address _root) {
        root = _root;
    }

    function newWrapper(address vault, address user) public returns (address) {
        address share = IERC7540(vault).share();

        ERC20 token = claimToken[share];
        if (address(token) == address(0)) {
            bytes32 salt = keccak256(abi.encodePacked(share, "claimToken"));
            token = new ClaimToken{salt: salt}(share);
            token.rely(root);
            claimToken[share] = token;
        }

        bytes32 salt = keccak256(abi.encodePacked(share, IERC7540(vault).asset(), user));

        RedemptionWrapper wrapper = new RedemptionWrapper{salt: salt}(vault, address(token), user);
        wrapper.rely(root);
        wrapper.deny(address(this));

        token.rely(address(wrapper));

        return address(wrapper);
    }
}
