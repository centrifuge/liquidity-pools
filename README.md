# Connectors
Connectors allows investors to provide liquidity into Centrifuge pools without having to bridge over to the Centrifuge chain. It provides a fully native experience for users on any supported chain.

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

To run all tests with additional fuzzing depth:
```sh
FOUNDRY_PROFILE=high forge test
```