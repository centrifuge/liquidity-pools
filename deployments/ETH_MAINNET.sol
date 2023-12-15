// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

contract Addresses {
    address public root = address(0x498016d30Cd5f0db50d7ACE329C07313a0420502);
    address public investmentManager = address(0xbBF0AB988691dB1892ADaF7F0eF560Ca4c6DD73A);
    address public poolManager = address(0x78E9e622A57f70F1E0Ec652A4931E4e278e58142);
    address public gateway = address(0x634F036fE66579E901c7bA34e33DF422E37A0037);
    address public escrow = address(0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936);
    address public userEscrow= address(0x9fc3A3bcEdc1CaB14EfC1B7ef45dFBDd3d17c9d7);
    address public router = address(0x8174D5f12Ce682459864D8C081f9635012Ab51c2);
    address public trancheTokenFactory = address(0x4aEFE6CeFEd5D0A30679E41C0B3Fee6cbAa6ADf6);
    address public liquidityPoolFactory = address(0x77F48b2c942E6f3ac2232568d560e423c441386a);
    address public restrictionManagerFactory = address(0xf4D7F6919eF0B495a2551F7299324961F29aE7aC);
    address public pauseAdmin = address(0xce86472007Ea37a5d0208f8C1559A37530c8067C);
    address public delayedAdmin = address(0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028);
    address public messages = address(0xAf9F6Ac63C057EB7F59b6Fae2c3d447191b58Ea5); 
    address public deployer = address(0x7270b20603FbB3dF0921381670fbd62b9991aDa4);
    address public admin = address(0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD); // multisig

    // deployed LPs
    address public anemoyToken = address(0x30baA3BA9D7089fD8D020a994Db75D14CF7eC83b);
}