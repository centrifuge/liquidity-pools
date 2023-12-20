#!/bin/bash

source .env

if [[ -z "$ROUTER" ]]; then
    error_exit "ROUTER is not defined"
fi
echo "Router = $ROUTER"

if [[ -z "$RPC_URL" ]]; then
    error_exit "RPC_URL is not defined"
fi
echo "RPC endpoint = $RPC_URL"

if [[ -z "$PRIVATE_KEY" ]]; then
    error_exit "PRIVATE_KEY is not defined"
fi

if [[ -z "$CHAIN_ID" ]]; then
    error_exit "CHAIN_ID is not defined"
fi
echo "Chain ID = $CHAIN_ID"

if [[ -z "$ETHERSCAN_KEY" ]]; then
    error_exit "ETHERSCAN_KEY is not defined"
fi

if [[ -z "$ETHERSCAN_URL" ]]; then
    error_exit "ETHERSCAN_URL is not defined"
fi
echo "Etherscan endpoint = $ETHERSCAN_URL"

if [[ -z "$ADMIN" ]]; then
    error_exit "ADMIN is not defined"
fi
echo "Admin = $ADMIN"

if [[ -z "$PAUSERS" ]]; then
    error_exit "PAUSERS is not defined"
fi
echo "Pausers = $PAUSERS"

case "$ROUTER" in
  Permissionless|Axelar|Forwarder)
    forge script script/${ROUTER}.s.sol:${ROUTER}Script --optimize --slow --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_KEY --verifier-url $ETHERSCAN_URL $1
    ;;
  *)
    echo "Router should be one of Permissionless, Axelar, Forwarder"
    exit 1
    ;;
esac
