#!/bin/bash

source .env

if [[ -z "$RPC_URL" ]]; then
    error_exit "RPC_URL is not defined"
fi
echo "RPC endpoint = $RPC_URL"

if [[ -z "$ADAPTER" ]]; then
    error_exit "ADAPTER is not defined"
fi
echo "Adapter = $ADAPTER"

if [[ -z "$ADMIN" ]]; then
    error_exit "ADMIN is not defined"
fi
echo "Admin = $ADMIN"

case "$ADAPTER" in
  Permissionless|Axelar|Forwarder)
    forge script script/${Adapter}.s.sol:${ADAPTER}Script --optimize --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_KEY $1
    ;;
  *)
    echo "Adapter should be one of Permissionless, Axelar, Forwarder"
    exit 1
    ;;
esac
