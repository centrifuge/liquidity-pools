// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "@summa-tx/memview-sol/contracts/TypedMemView.sol";
import {ConnectorMessages} from "../../Messages.sol";

interface ConnectorLike {
  function addPool(uint64 poolId) external;
  function addTranche(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) external;
  function updateMember(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) external;
  function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint256 price) external;
}

contract ConnectorXCMRouter {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    ConnectorLike public immutable connector;

    address immutable centrifugeChainOrigin;

    event Pong(address indexed origin);

    constructor(address connector_, address centrifugeChainOrigin_) {
        connector = ConnectorLike(connector_);
        centrifugeChainOrigin = centrifugeChainOrigin_;
    }

    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "ConnectorXCMRouter/invalid-origin");
        _;
    }

    function handle(
        bytes memory _message
    ) external onlyCentrifugeChainOrigin {
        bytes29 _msg = _message.ref(0);
        if (ConnectorMessages.isAddPool(_msg) == true) {
            uint64 poolId = ConnectorMessages.parseAddPool(_msg);
            connector.addPool(poolId);
        } else if (ConnectorMessages.isAddTranche(_msg) == true) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) = ConnectorMessages.parseAddTranche(_msg);
            connector.addTranche(poolId, trancheId, tokenName, tokenSymbol);
        } else if (ConnectorMessages.isUpdateMember(_msg) == true) {
            (uint64 poolId, bytes16 trancheId, address user, uint256 amount) = ConnectorMessages.parseUpdateMember(_msg);
            connector.updateMember(poolId, trancheId, user, amount);
        } else if (ConnectorMessages.isUpdateTokenPrice(_msg) == true) {
            (uint64 poolId, bytes16 trancheId, uint256 price) = ConnectorMessages.parseUpdateTokenPrice(_msg);
            connector.updateTokenPrice(poolId, trancheId, price);
        } else {
            require(false, "invalid-message");
        }
    }
}
