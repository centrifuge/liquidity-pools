#!/bin/bash

source .env

forge script script/Permissionless.s.sol:PermissionlessScript --optimize --sizes --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_KEY -vvvv