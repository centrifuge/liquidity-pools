# Connectors
Connectors enables seamless deployment of Centrifuge RWA pools on any EVM-compatible blockchain.

## How it works
<a href="https://github.com/centrifuge/connectors">
  <img alt="Centrifuge" src="contracts.svg">
</a>

- **Investor Pool** (WIP): A [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/) compatible contract that enables investors to deposit and withdraw stablecoins to invest in tranches of pools.
- **Tranche token**: An [ERC-20](https://ethereum.org/en/developers/docs/standards/tokens/erc-20/) token for the tranche, linked to a `Memberlist` that manages transfer restrictions.
- **Connectors**: The core business logic contract that handles pool creation, tranche deployment, managing investments and sending tokens to the `Escrow`, and more.
- **Gateway**: Intermediary contract that encodes and decodes messages and includes checks such as rate limits.
- **Routers**: Contracts that handle communication of messages to and from Centrifuge Chain.

## Developing
#### Getting started
```sh
git clone git@github.com:centrifuge/connectors.git
cd connectors
forge update
cd lib/monorepo && yarn && cd ..
```

#### Testing
To run all tests locally:
```sh
forge test
```

## License
This codebase is licensed under [GNU Lesser General Public License v3.0](https://github.com/centrifuge/centrifuge-chain/blob/main/LICENSE).
