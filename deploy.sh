source .env

if [ -z $ETHERSCAN_KEY ]; then
  forge script script/Connector.s.sol:ConnectorScript --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv
else
  forge script script/Connector.s.sol:ConnectorScript --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY -vvvv
fi

