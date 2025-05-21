<p align="center">
    <img src="./assets/DIA_logo.png" alt="Dia logo" width="200" height="auto" style="padding: 20px;">
</p>

# lumina-staking

This repository contains the DIA Lumina staking smart contracts, along with their tests. There are two main contracts:

1. [`DIAExternalStaking.sol`](./contracts/DIAExternalStaking.sol): a permissionless staking contract that allows anyone to stake DIA tokens and earn rewards, with support for delegation and principal/reward sharing.
2. [`DIAWhitelistedStaking.sol`](./contracts/DIAWhitelistedStaking.sol): a permissioned staking pool designed for whitelisted participants that supports direct staking and delegation.

For a high-level introduction to Lumina, see [Lumina docs](https://docs.diadata.org/).

## Structure

```
.
├── contracts
│   ├── DIAExternalStaking.sol
│   ├── DIARewardsDistribution.sol
│   ├── DIAStakingCommons.sol
│   ├── DIAWhitelistedStaking.sol
│   ├── StakingErrorsAndEvents.sol
│   └── WDIA.sol
├── lib
├── script
│   ├── DeployStaking.s.sol
│   └── GenerateWallets.s.sol
├── test-foundry
    ├── calc-seconduser.t.sol
    ├── calc.t.sol
    ├── DIAExternalStaking.t.sol
    ├── DIAExternalStakingE2E.t.sol
    ├── DIAStakingFuzzTest.t.sol
    ├── DIAStakingTestE2E.t.sol
    └── DIAWhitelistedStaking.t.sol
```

### Contracts

- `DIAExternalStaking.sol`: A permissionless staking contract that allows anyone to stake DIA tokens and earn rewards, with support for delegation and reward sharing.
- `DIARewardsDistribution.sol`: An abstract contract that provides base functionality for managing token rewards distribution, including reward rate and wallet management.
- `DIAStakingCommons.sol`: A base contract that implements common staking functionality shared between different staking contracts, including stake tracking, withdrawal limits, and share management.
- `DIAWhitelistedStaking.sol`: A permissioned staking contract that only allows whitelisted addresses to stake DIA tokens and earn rewards, with support for delegation and reward sharing.
- `StakingErrorsAndEvents.sol`: A contract that defines common errors and events used across the staking system, providing standardized error handling and event emission.
- `WDIA.sol`: A simple wrapped DIA token contract that allows users to deposit and withdraw DIA tokens, implementing basic ERC20 functionality.

## Installation

Clone the repository:

```bash
git clone https://github.com/diadata-org/lumina-staking.git
```

Install dependencies:

```bash
npm install
```

Make sure you have foundry installed. The instructions can be found in their [documentation](https://book.getfoundry.sh/getting-started/installation).

## Usage

Compile contracts:

```bash
forge build
```

Run tests:

```bash
forge test
```

For contract interaction examples, refer to the test files in [`/test-foundry`](./test-foundry/).
