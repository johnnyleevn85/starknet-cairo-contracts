<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/starknet-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/starknet-light.png">
  <img alt="Your logo" src="assets/starknet-light.png">
</picture>
</div>

<div align="center">

[![License: Apache2.0](https://img.shields.io/badge/License-Apache2.0-green.svg)](LICENSE)
</div>

# Starknet LBTC smart contracts

## Lombard Finance documentation

[Website](https://www.lombard.finance/) | [Docs](https://docs.lombard.finance/)

## Content

- [Overview](#overview)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Getting help](#getting-help)
- [Build and Test](#build-and-test)
- [Audit](#audit)
- [Security](#security)

## Overview

LBTC is liquid Bitcoin; it's yield-bearing, cross-chain, and 1:1 backed by BTC. LBTC enables yield-bearing BTC to move cross-chain without fragmenting liquidity, and is designed to seamlessly integrate Bitcoin into the decentralized finance (DeFi) ecosystem while maintaining the security and integrity of the underlying asset.

| Smart contract   | Description                                                                                                                            |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| [LBTC](packages/token)             | ERC20 token to interact with protocol.                                                                                                 |
| [Bascule](packages/bascule)          | Bascule drawbridge designed to prevent bridge hacks before they hit the chain.                                                         |
| [Consortium](packages/consortium)       | The contract utilizes notary consortium multi-signature verification.                                                                  |
| [Bridge](packages/bridge)           | Multi-factor bridge.                                                                                                                   |
| [StakeAndBake](packages/stake_and_bake)     | Convenience contract for users who wish to stake their `BTC` and deposit `LBTC` in a vault in the same transaction.                    |
| [Vault](packages/vault)            | ERC4626 vault to deposit `LBTC` and earn yield.                                                                                        |
| [Manual Strategy](packages/manual_strategy)  | Contract that gets the `LBTC` from the vault and is controlled by an off-chain operator to generate the yield.                         |

## Dependencies

- Cairo dependencies such as [Scarb](https://docs.swmansion.com/scarb/) and [Starknet foundry](https://foundry-rs.github.io/starknet-foundry/index.html) - install using [starkup](https://github.com/software-mansion/starkup).

## Installation

Clone the repo and from within the projects root folder run:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.starkup.dev | sh
```

## Getting help

Reach out to the maintainer at any of the following:

- [GitHub Discussions](https://github.com/starkware-libs/sn-lbtc/discussions)
- Contact options listed on this [GitHub profile](https://github.com/starkware-libs)

## Build and Test

Build the contracts from the repo root:

```bash
scarb build

```

To run the tests, execute:

```bash
scarb test
```

## Audit

Find the latest audit report in [docs/audit](docs/audit).

## Security

Starknet LBTC follows good practices of security, but 100% security cannot be assured. Starknet LBTC is provided "as is" without any warranty. Use at your own risk.

For more information and to report security issues, please refer to our [security documentation](https://github.com/starkware-libs/sn-lbtc/blob/main/docs/SECURITY.md).
