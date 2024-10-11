// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Wrapper, IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IPermissionlessWrapperFactory} from "src/interfaces/factories/IPermissionlessWrapper.sol";

contract PermissionlessWrapper is ERC20, IERC20Wrapper {
    address public underlying;

    constructor(address underlying_) ERC20(IERC20Metadata(underlying_).decimals()) {
        underlying = underlying_;
    }

    function depositFor(address account, uint256 value) external returns (bool) {
        require(
            IERC20Metadata(underlying).transferFrom(msg.sender, address(this), value),
            "PermissionlessWrapper/failed-transfer"
        );
        super.mint(account, value);

        return true;
    }

    function withdrawTo(address account, uint256 value) external returns (bool) {
        super.burn(account, value);

        IERC20Metadata(underlying).transfer(account, value);
        return true;
    }
}

contract PermissionlessWrapperFactory is IPermissionlessWrapperFactory {
    // --- Deployment ---
    /// @inheritdoc IPermissionlessWrapperFactory
    function newWrapper(bytes32 salt, address underlying, string memory name, string memory symbol)
        external
        returns (address)
    {
        PermissionlessWrapper wrapper = new PermissionlessWrapper{salt: salt}(underlying);

        wrapper.file("name", name);
        wrapper.file("symbol", symbol);

        wrapper.rely(msg.sender);
        wrapper.deny(address(this));

        emit DeployPermissionlessWrapper(msg.sender, underlying, address(wrapper));
        return address(wrapper);
    }
}
