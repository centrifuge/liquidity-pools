#!/bin/bash

source .env

if [[ $# -eq 0 ]] ; then
    echo "Router argument missing"
    exit 1
fi

if [[ -z "$RPC_URL" ]]; then
    error_exit "RPC_URL is not defined"
fi
echo "RPC URL = $ETH_RPC_URL"

if [[ -z "$ETH_FROM" ]]; then
    error_exit "ETH_FROM is not defined"
fi
echo "Account = $ETH_FROM"
echo "Network = $(seth chain)"
echo "Balance = $(echo "$(seth balance $ETH_FROM)/10^18" | bc -l) ETH"

case "$1" in
  Permissionless|AxelarEVM|AxelarXCM)
    forge script script/$1.s.sol:$1Script --optimize --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_KEY $2
    ;;
  *)
    echo "Router should be one of Permissionless, AxelarEVM, AxelarXCM"
    exit 1
    ;;
esac
