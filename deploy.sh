#!/bin/bash

source .env

if [[ -z "$RPC_URL" ]]; then
    error_exit "RPC_URL is not defined"
fi
echo "RPC endpoint = $RPC_URL"

if [[ -z "$ROUTER" ]]; then
    error_exit "ROUTER is not defined"
fi
echo "Router = $ROUTER"

if [[ -z "$ADMIN" ]]; then
    error_exit "ADMIN is not defined"
fi
echo "Admin = $ADMIN"

case "$ROUTER" in
  Permissionless|Axelar|Forwarder)
    forge script script/${ROUTER}.s.sol:${ROUTER}Script --optimize --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_KEY $1
    ;;
  *)
    echo "Router should be one of Permissionless, Axelar, Forwarder"
    exit 1
    ;;
esac
