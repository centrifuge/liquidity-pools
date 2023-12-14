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

if [[ -z "$DELAYED_ADMIN" ]]; then
    error_exit "DELAYED_ADMIN is not defined"
fi
echo "Delayed Admin = $DELAYED_ADMIN"

if [[ -z "$PAUSE_ADMINS" ]]; then
    error_exit "PAUSE_ADMINS is not defined"
fi
echo "Pause Admins = $PAUSE_ADMINS"

case "$ROUTER" in
  Permissionless|Axelar|Forwarder)
    forge script script/${ROUTER}.s.sol:${ROUTER}Script --optimize --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_KEY $1
    ;;
  *)
    echo "Router should be one of Permissionless, Axelar, Forwarder"
    exit 1
    ;;
esac
