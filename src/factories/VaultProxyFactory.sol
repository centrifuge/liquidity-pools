// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {ICentrifugeRouter} from "src/interfaces/ICentrifugeRouter.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {IVaultProxy, IVaultProxyFactory} from "src/interfaces/factories/IVaultProxy.sol";

contract VaultProxy is IVaultProxy {
    IERC20 public immutable asset;
    IERC20 public immutable share;
    address public immutable user;
    address public immutable vault;
    ICentrifugeRouter public immutable router;

    constructor(address router_, address vault_, address user_) {
        asset = IERC20(IERC7540Vault(vault_).asset());
        share = IERC20(IERC7540Vault(vault_).share());
        user = user_;
        vault = vault_;
        router = ICentrifugeRouter(router_);
    }

    /// @inheritdoc IVaultProxy
    function requestDeposit() external payable {
        uint256 assets = asset.allowance(user, address(this));
        require(assets > 0, "VaultProxy/zero-asset-allowance");
        asset.transferFrom(user, address(router), assets);
        router.requestDeposit{value: msg.value}(vault, assets, user, address(router), msg.value);
    }

    /// @inheritdoc IVaultProxy
    function claimDeposit() external {
        uint256 maxMint = IERC7540Vault(vault).maxMint(user);
        IERC7540Vault(vault).mint(maxMint, address(user), user);
    }

    /// @inheritdoc IVaultProxy
    function requestRedeem() external payable {
        uint256 shares = share.allowance(user, user);
        require(shares > 0, "VaultProxy/zero-share-allowance");
        share.transferFrom(user, address(router), shares);
        router.requestRedeem{value: msg.value}(vault, shares, user, address(router), msg.value);
    }

    /// @inheritdoc IVaultProxy
    function claimRedeem() external {
        uint256 maxWithdraw = IERC7540Vault(vault).maxWithdraw(address(this));
        IERC7540Vault(vault).withdraw(maxWithdraw, address(user), address(this));
    }
}

interface VaultProxyFactoryLike {
    function newVaultProxy(address poolManager, bytes32 destination) external returns (address);
}

/// @title  Vault investment proxy factory
/// @notice Used to deploy vault proxies that investors can give ERC20 approval for assets or shares
///         which anyone can then permissionlessly trigger the requests to the vaults to. Can be used
///         by integrations that can only support ERC20 approvals and not arbitrary contract calls.
contract VaultProxyFactory is IVaultProxyFactory {
    address public immutable router;

    /// @inheritdoc IVaultProxyFactory
    mapping(bytes32 id => address proxy) public proxies;

    constructor(address router_) {
        router = router_;
    }

    /// @inheritdoc IVaultProxyFactory
    function newVaultProxy(address vault, address user) public returns (address) {
        bytes32 id = keccak256(abi.encodePacked(vault, user));
        require(proxies[id] == address(0), "VaultProxyFactory/proxy-already-deployed");

        address proxy = address(new VaultProxy(router, vault, user));
        proxies[id] = proxy;

        emit DeployVaultProxy(vault, user, proxy);
        return proxy;
    }
}
