// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import "./interfaces/IERC7540.sol";

contract CentrifugeRouter is Auth {
    address payable immutable gateway;
    mapping(address => mapping(address => uint256)) public lockedRequests;

    constructor(address payable gateway_) {
        gateway = gateway_;
    }

    // --- Administration ---
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // TODO distinguish the source of the TX  whether it comes from CentrifugeRouter or ERC7540Vault directrly.
    // --- Deposit ---
    function requestDeposit(address vault, uint256 amount) external payable {
        require(msg.value > 0, "CentrifugeRouter/not-enough-funds");
        gateway.transfer(msg.value);
        IERC7540Vault(vault).requestDeposit(amount, msg.sender, msg.sender);
    }

    function lockDepositRequest(address vault, uint256 amount) external {
        SafeTransferLib.safeTransferFrom(IERC7540Vault(vault).asset(), msg.sender, address(this), amount);
        lockedRequests[msg.sender][vault] += amount;
    }

    function unlockDepositRequest(address vault) external {
        uint256 lockedRequest = lockedRequests[msg.sender][vault];
        require(lockedRequest > 0, "CentrifugeRouter/investor-has-no-locked-balance");
        lockedRequests[msg.sender][vault] = 0;
        SafeTransferLib.safeTransfer(IERC7540Vault(vault).asset(), msg.sender, lockedRequest);
    }

    function executeLockedDepositRequest(address vault, address investor) external {
        uint256 lockedRequest = lockedRequests[investor][vault];
        require(lockedRequest > 0, "CentrifugeRouter/investor-has-no-balance");
        lockedRequests[investor][vault] = 0;
        IERC7540Vault(vault).requestDeposit(lockedRequest, msg.sender, address(this));
    }

    function claimDeposit(address vault, address investor) external {
        uint256 maxDeposit = IERC7540Vault(vault).maxDeposit(investor);
        require(maxDeposit > 0, "CentrifugeRouter/investor-has-no-balance-to-claim");
        IERC7540Vault(vault).deposit(maxDeposit, investor, investor);
    }

    // --- Redeem ---
    function requestRedeem(address vault, uint256 amount) external {
        IERC7540Vault(vault).requestRedeem(amount, msg.sender, msg.sender);
    }

    function claimRedeem(address vault, address investor) external {
        uint256 maxRedeem = IERC7540Vault(vault).maxRedeem(investor);
        require(maxRedeem > 0, "CentrifugeRouter/investor-has-no-balance-to-claim");
        IERC7540Vault(vault).redeem(maxRedeem, investor, investor);
    }
}
