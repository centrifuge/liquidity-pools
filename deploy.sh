#!/bin/bash

source .env

forge script script/Axelar-EVM.s.sol:AxelarEVMScript --optimize --sizes --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_KEY -vvvv