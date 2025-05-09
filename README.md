# Pareto USP contracts [![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

This repository contains the Pareto Synthetic Dollar contracts:
- `ParetoDollar`: the main contract that mints and redeems USP
- `ParetoDollarQueue`: the contract that manages the deposits and redeems into Pareto Credit Vaults and ERC4626 vaults. It also manages users redeem requests
- `ParetoDollarStaking`: the contract that allows users to stake their USP for sUSP and earn yield from Pareto Credit Vaults and ERC4626 vaults.

## Installing Dependencies

```sh
$ bun install

or

$ yarn install
```
and

```sh
$ forge install
```

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ bun run build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ bun run clean
```

### Deploy

In `Deploy.s.sol` in `run()` you can set network used for the deployment.

```sh
$ bun run deploy
```

### Upgrade

In `Upgrade.s.sol` in `run()` you can set network used and other params like proxy.

```sh
$ bun run upgrade
```

### Test

Run the tests:

```sh
$ bun run test
```

### Gas Usage

Get a gas report:

```sh
$ bun run test --gas-report
```
