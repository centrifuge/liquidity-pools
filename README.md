# Liquidity Pools [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/centrifuge/liquidity-pools/blob/main/LICENSE)

[gha]: https://github.com/centrifuge/liquidity-pools/actions
[gha-badge]: https://github.com/centrifuge/liquidity-pools/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

Liquidity Pools enable seamless deployment of Centrifuge RWA pools on any EVM-compatible blockchain.

## How it works

![Architecture](https://centrifuge.mypinata.cloud/ipfs/QmYLCvEDVyRr4TR3i9sUHADdm4fPkYaLwo6HzuBCbHL6RZ)

Investors can invest in multiple tranches for each RWA pool. Each of these tranches is a separate deployment of a Liquidity Pool and a Tranche Token.

- [**Liquidity Pool**](https://github.com/centrifuge/liquidity-pools/blob/main/src/LiquidityPool.sol): An [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540) (extension of [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/)) compatible contract that enables investors to deposit and withdraw stablecoins to invest in tranches of pools.
- [**Tranche Token**](https://github.com/centrifuge/liquidity-pools/blob/main/src/token/Tranche.sol): An [ERC-20](https://ethereum.org/en/developers/docs/standards/tokens/erc-20/) token for the tranche, linked to a [`RestrictionManager`](https://github.com/centrifuge/liquidity-pools/blob/main/src/token/RestrictionManager.sol) that manages transfer restrictions. Prices for tranche tokens are computed on Centrifuge.

The deployment of these tranches and the management of investments is controlled by the underlying InvestmentManager, TokenManager, Gateway, and Routers.

- [**Investment Manager**](https://github.com/centrifuge/liquidity-pools/blob/main/src/InvestmentManager.sol): The core business logic contract that handles pool creation, tranche deployment, managing investments and sending tokens to the [`Escrow`](https://github.com/centrifuge/liquidity-pools/blob/main/src/Escrow.sol), and more.
- [**Pool Manager**](https://github.com/centrifuge/liquidity-pools/blob/main/src/PoolManager.sol): The second business logic contract that handles currency bookkeeping, and transferring tranche tokens as well as currencies.
- [**Gateway**](https://github.com/centrifuge/liquidity-pools/blob/main/src/gateway/Gateway.sol): Intermediary contract that encodes and decodes messages using [`Messages`](https://github.com/centrifuge/liquidity-pools/blob/main/src/gateway/Messages.sol) and handles routing to/from Centrifuge.
- [**Routers**](https://github.com/centrifuge/liquidity-pools/tree/main/src/gateway/routers): Contracts that handle communication of messages to and from Centrifuge Chain.

## Developing

#### Getting started

```sh
git clone git@github.com:centrifuge/liquidity-pools.git
cd liquidity-pools
forge update
```

#### Testing

To run all tests locally:

```sh
forge test
```

## Deploying

#### Setup

Liquidity Pools uses [Sphinx](https://sphinx.dev/) for crosschain deployments. To deploy the contracts:

```sh
cp .env.example .env
```

and fill in the required environment variables. Then run:

```sh
yarn install
yarn sphinx install
```

#### Configure

Cconfigure the deployment in script/Deployer.sol:

```solidity:script/Deployer.sol
function configureSphinx() public override {
    sphinxConfig.owners = [address(0x423420Ae467df6e90291fd0252c0A8a637C1e03f)];
    sphinxConfig.orgId = "clsypbcrw0001zqwy1arndx1t";
    sphinxConfig.projectName = "Liquidity_Pools";
    sphinxConfig.threshold = 1;
    sphinxConfig.testnets = ["ethereum-testnet"];
    sphinxConfig.mainnets = ["ethereum-mainnet", "arbitrum-mainnet", "celo-mainnet", "base-mainnet"];
}
```

and foundry.toml:

```toml:foundry.toml
[rpc_endpoints]
ethereum-mainnet = "https://eth.api.onfinality.io/rpc?apikey=${ONFINALITY_API_KEY}"
arbitrum-mainnet = "https://arbitrum.api.onfinality.io/rpc?apikey=${ONFINALITY_API_KEY}"
celo-mainnet = "https://celo.api.onfinality.io/rpc?apikey=${ONFINALITY_API_KEY}"
base-mainnet = "https://base.api.onfinality.io/rpc?apikey=${ONFINALITY_API_KEY}"
ethereum-testnet = "https://eth-sepolia.api.onfinality.io/rpc?apikey=${ONFINALITY_API_KEY}"
```

#### Propose

Sphinx deploys by first proposing deployments, which then need to be approved by a gnosis safe member before they're executed onchain. The safe is automatically generated and assigned to you on account creation at [sphinx.dev](https://sphinx.dev/).

You can propose via CI by pushing a release tag:

```sh
git tag release-v1.0
git push origin release-v1.0
```

Or manually with:

```sh
./deploy.sh
```

#### Deploy

To deploy a proposal login to [sphinx.dev](https://sphinx.dev/) and approve the pending proposal.

## Audit reports

| Auditor   | Report link                                                                                                                                    |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Code4rena | [`September 2023 - Code4rena Report`](https://code4rena.com/reports/2023-09-centrifuge)                                                        |
| SRLabs    | [`September 2023 - SRLabs Report`](https://github.com/centrifuge/liquidity-pools/blob/main/audits/2023-09-SRLabs.pdf)                          |
| Spearbit  | [`October 2023 - Cantina Managed Report`](https://github.com/centrifuge/liquidity-pools/blob/main/audits/2023-10-Spearbit-Cantina-Managed.pdf) |

## License

This codebase is licensed under [GNU Lesser General Public License v3.0](https://github.com/centrifuge/liquidity-pools/blob/main/LICENSE).

```

```
