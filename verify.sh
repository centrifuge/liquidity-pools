#!/bin/bash

source .env

if [ -z "$RPC_URL" ] || [ -z "$ETHERSCAN_KEY" ] || [ -z "$VERIFIER_URL" ] || [ -z "$CHAIN_ID" ]; then
    echo "Error: RPC_URL, ETHERSCAN_KEY, VERIFIER_URL, and CHAIN_ID must be set in the .env file."
    exit 1
fi

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 {liquidityPool|trancheToken|restrictionManager} contract_address"
    exit 1
fi

type=$1
contract_address=$2

if [ "$type" == "restrictionManager" ]; then
    token=$(cast call $contract_address 'token()(address)' --rpc-url $RPC_URL)
    echo "token: $token"
    forge verify-contract --constructor-args $(cast abi-encode "constructor(address)" $token) --watch --etherscan-api-key $ETHERSCAN_KEY $contract_address src/token/RestrictionManager.sol:RestrictionManager --verifier-url $VERIFIER_URL --chain $CHAIN_ID
elif [ "$type" == "trancheToken" ]; then
    decimals=$(cast call $contract_address 'decimals()(uint8)' --rpc-url $RPC_URL)
    echo "decimals: $decimals"
    forge verify-contract --constructor-args $(cast abi-encode "constructor(uint8)" $decimals) --watch --etherscan-api-key $ETHERSCAN_KEY $contract_address src/token/Tranche.sol:TrancheToken --verifier-url $VERIFIER_URL --chain $CHAIN_ID
elif [ "$type" == "liquidityPool" ]; then
    poolId=$(cast call $contract_address 'poolId()(uint64)' --rpc-url $RPC_URL | awk '{print $1}')
    trancheId=$(cast call $contract_address 'trancheId()(bytes16)' --rpc-url $RPC_URL | cut -c 1-34)
    asset=$(cast call $contract_address 'asset()(address)' --rpc-url $RPC_URL)
    share=$(cast call $contract_address 'share()(address)' --rpc-url $RPC_URL)
    escrow=$(cast call $contract_address 'escrow()(address)' --rpc-url $RPC_URL)
    manager=$(cast call $contract_address 'manager()(address)' --rpc-url $RPC_URL)
    echo "poolId: $poolId"
    echo "trancheId: $trancheId"
    echo "asset: $asset"
    echo "share: $share"
    echo "escrow: $escrow"
    echo "manager: $manager"
    forge verify-contract --constructor-args $(cast abi-encode "constructor(uint64,bytes16,address,address,address,address)" $poolId $trancheId $asset $share $escrow $manager) --watch --etherscan-api-key $ETHERSCAN_KEY $contract_address src/ERC7540Vault.sol:ERC7540Vault --verifier-url $VERIFIER_URL --chain $CHAIN_ID
else
    echo "Error: Invalid contract type. Choose from liquidityPool, trancheToken, or restrictionManager."
    exit 1
fi