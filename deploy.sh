#!/bin/bash
source .env

if [[ -z "$ROUTER" ]]; then
  ROUTER=""
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --router|-r)
      ROUTER="$2"
      shift 2
      ;;
    --networks|-n)
      networks="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$ROUTER" ]]; then
  echo "Please provide the router using the --router or -r flag, or define it in the .env file"
  exit 1
fi

case "$ROUTER" in
  Permissionless|Axelar|Forwarder)
    echo "Router = $ROUTER"
    ;;
  *)
    echo "Router must be one of Permissionless, Axelar, or Forwarder."
    exit 1
    ;;
esac

if [[ -z "$ADMIN" ]]; then
  error_exit "ADMIN is not defined"
fi
echo "Admin = $ADMIN"

if [[ -z "$PAUSERS" ]]; then
  error_exit "PAUSERS is not defined"
fi
echo "Pausers = $PAUSERS"

if [[ -z "$networks" ]]; then
  echo "Please provide 'mainnets', 'testnets', or a network from foundry.toml, using the --networks or -n flag"
  exit 1
fi

npx sphinx propose script/${ROUTER}.s.sol --networks ${networks} --dry-run