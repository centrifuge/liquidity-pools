// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import "./interfaces/IERC7540.sol";

interface IERC7540ExtLike {
    function deposit(uint256 assets, address receiver, address owner) external returns (uint256 shares);
}

interface IERC20Like {
    function approve(address spender, uint256 value) external returns (bool);
}

contract CentrifugeRouter is Auth {
    mapping(address => mapping(address => uint256)) public lockedRequests;

    // --- Interactions ---

    // --- Deposit ---
    function requestDeposit(address vault, uint256 amount) external {
        requestDeposit(vault, amount, msg.sender);
    }

    function requestDeposit(address vault, uint256 amount, address investor) public {
        SafeTransferLib.safeTransferFrom(IERC7540(vault).asset(), investor, address(this), amount);
        IERC20Like(IERC7540(vault).asset()).approve(vault, amount); // option to add approve function, make poolManager
            // ward and create global approval on vault deployment
        IERC7540(vault).requestDeposit(amount, investor, address(this), "");
    }

    function lockDepositRequest(address vault, uint256 amount) external {
        SafeTransferLib.safeTransferFrom(IERC7540(vault).asset(), msg.sender, address(this), amount);
        lockedRequests[msg.sender][vault] += amount;
    }

    function unlockDepositRequest(address vault) external {
        uint256 lockedRequest = lockedRequests[msg.sender][vault];
        require(lockedRequest > 0, "CentrifugeRouter/investor-has-no-locked-balance");
        lockedRequests[msg.sender][vault] = 0;
        SafeTransferLib.safeTransfer(IERC7540(vault).asset(), msg.sender, lockedRequest);
    }

    function executeLockedDepositRequest(address vault, address investor) external {
        uint256 lockedRequest = lockedRequests[investor][vault];
        require(lockedRequest > 0, "CentrifugeRouter/investor-has-no-balance");
        lockedRequests[investor][vault] = 0;
        IERC20Like(IERC7540(vault).asset()).approve(vault, lockedRequest);
        IERC7540(vault).requestDeposit(lockedRequest, investor, address(this), "");
    }

    function claimDeposit(address vault, address investor) external {
        uint256 maxDeposit = IERC7540(vault).maxDeposit(investor);
        require(maxDeposit > 0, "CentrifugeRouter/investor-has-no-balance-to-claim");
        IERC7540ExtLike(vault).deposit(maxDeposit, investor, investor);
    }

    // --- Redeem ---
    function requestRedeem(address vault, uint256 amount) external {
        requestRedeem(vault, amount, msg.sender);
    }

    function requestRedeem(address vault, uint256 amount, address investor) public {
        SafeTransferLib.safeTransferFrom(IERC7540(vault).share(), investor, address(this), amount);
        IERC7540(vault).requestRedeem(amount, investor, address(this), "");
    }

    function claimRedeem(address vault, address investor) external {
        uint256 maxRedeem = IERC7540(vault).maxRedeem(investor);
        require(maxRedeem > 0, "CentrifugeRouter/investor-has-no-balance-to-claim");
        IERC7540(vault).redeem(maxRedeem, investor, investor);
    }

    // --- ERC20 Recovery ---
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }
}
