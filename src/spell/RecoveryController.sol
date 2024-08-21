pragma solidity 0.8.26;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external;
}

contract RecoveryController {
    address public constant WCFG = address(0xc221b7E65FfC80DE234bbB6667aBDd46593D34F0);
    address public constant RWA_VAULT = address(0xCDd95E8738Edc0733583EE484a3050a05Ee87Ff5);
    address public constant RECOVERY_WALLET = address(0x1514E1d289157F5403B80872bd82FAF7CBA1843C); // replace recovery
        // wallet address

    constructor() {}

    function recover() external {
        uint256 recoveryAmount = IERC20(WCFG).balanceOf(RWA_VAULT);
        IERC20(WCFG).transferFrom(RWA_VAULT, RECOVERY_WALLET, recoveryAmount);
    }
}
