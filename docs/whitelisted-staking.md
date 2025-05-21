# DIAWhitelistedStaking Pool

`DIAWhitelistedStaking.sol` is a permissioned staking pool designed for whitelisted participants that supports direct staking and delegation.

The contract implements a linear rewards mechanism, meaning that staking rewards accrue at a constant rate over time. Each staker’s rewards are calculated based on the amount of tokens staked and the duration of their stake. Rewards are distributed proportionally and can be claimed or withdrawn according to the contract’s rules. The system also supports splitting rewards between the beneficiary and a principal payout wallet (delegator), allowing for flexible reward sharing arrangements.

A Whitelisted Staker is typically a node operator within the Distributed Feeder Network (DFN). They can either receive stake delegation or stake directly for themselves and earn rewards in both cases.

Features:

- Only addresses explicitly added to the whitelist by the contract owner can participate in the pool.
- Rewards earned from staking can be split between the beneficiary (typically the node operator) and a principal payout wallet (delegator).
- Users can have multiple stakes, each tracked separately with different roles and reward splits.
- Support for 3 types of roles:
  - Beneficiary
  - PrincipalPayoutWallet (can be the delegator themselves)
  - PrincipalUnstaker (can be the delegator themselves)

Staking information is stored in a struct:

```solidity
    struct StakingStore {
        address beneficiary;
        address principalPayoutWallet;
        address principalUnstaker;
        uint256 principal;
        uint256 reward;
        uint256 paidOutReward;
        uint64 stakingStartTime;
        uint64 unstakingRequestTime;
        uint32 principalWalletShareBps;
    }
```

# Formulas

For a given user's stake `StakingStore storage currentStore = stakingStores[stakingStoreIndex]`, the following formulas apply:

### rewards

`currentStore.rewards = (rewardRatePerDay * passedDays * currentStore.principal) / 10000` where `passedDays = passedSeconds / (24 * 60 * 60)`

### rewardsToSend

`rewardsToSend = currentStore.rewards - currentStore.paidOutReward`

### principalWalletReward

`principalWalletReward  = (rewardToSend * currentStore.principalWalletShareBps) / 10000`

### beneficiaryReward

`beneficiaryReward = rewardToSend - principalWalletReward`

# Methods

## Add/Remove Staker

### addWhitelistedStaker(address newStakerAddress)

`addWhitelistedStaker` adds a whitelisted address that is approved to participate in the staking pool.

Checks:

- Caller is owner (`onlyOwner` modifier)
- Address is not whitelisted already

Effects:

- Sets `stakingWhitelist[newStakerAddress] = true;`

Interactions:

- Emits `StakerAddressAdded`

### removeWhitelistedStaker(address stakerAddressToRemove)

`removeWhitelistedStaker` revokes the whitelisted status from an address.

Checks:

- Caller is owner (`onlyOwner` modifier)
- Address is whitelisted `!stakingWhitelist[stakerAddressToRemove]`

Effects:

- `stakingWhitelist[stakerAddressToRemove] = false;`

Interactions:

- Emits `StakerAddressRemoved(stakerAddressToRemove);`

## Staking

### stakeForAddress(address beneficiaryAddress, uint256 amount, uint32 principalWalletShareBps)

`stakeForAddress` delegates a stake to a beneficiary and sets the reward share % for the delegator. The remaining % goes to the beneficiary.

Checks:

- beneficiaryAddress is whitelisted

Interactions:

- Calls `_internalStakeForAddress(msg.sender, beneficiaryAddress, amount, principalWalletShareBps)`

### stake(uint256 amount)

`stake` deposits an amount to the delegator’s balance and sets their rewards share % to 100% (i.e. all the rewards go to the delegator).

Checks:

- msg.sender is whitelisted

Interactions:

- Calls `_internalStakeForAddress(msg.sender, msg.sender, amount, 10_000)`

## Unstaking & Claiming

### unstake(uint256 stakingStoreIndex)

`unstake` sends rewards accumulated to the beneficiary & delegator. Can be called at any point in time.

Checks:

- Caller is either the beneficiary or the delegator (`onlyBeneficiaryOrPayoutWallet` modifier).
- Caller made an unstake request.
- Unstake (or waiting) period has elapsed.

Effects:

- Calls `updateReward(stakingStoreIndex)` to calculate the rewards.
- Subtracts the rewards received from the new rewards `rewardToSend = currentStore.reward - currentStore.paidOutReward;`
- Increments the `currentStore.paidOutReward` by `rewardToSend`
- Calculates the reward share of the delegator (`principalWalletReward`)
- Calculates the reward share of the beneficiary `beneficiaryReward = rewardToSend - principalWalletReward;`

Interactions:

- safeTransfers the `principalWalletReward` from the `rewardsWallet` to the delegator (or principalPayoutWallet).
- safeTransfers the `beneficiaryReward` from the `rewardsWallet` to the beneficiary.
- Sets `currentStore.unstakingRequestTime = 0;`.
- Sets `currentStore.reward = 0;`.
- Sets `currentStore.stakingStartTime = uint64(block.timestamp);`.
- Emits `Unstaked(stakingStoreIndex, 0, principalWalletReward, beneficiaryReward, currentStore.principalPayoutWallet, currentStore.beneficiary)`

### unstakePrincipal(uint256 stakingStoreIndex, uint256 amount)

`unstakePrincipal` withdraws an amount from the staker's principal. Requires a withdrawal request submission via `requestUnstake(uint256 stakingStoreIndex)`.

Checks:

- Caller made an unstake request.
- Unstake (or waiting) period has elapsed.
- Call is the principalUnstaker.
- Amount doesn’t exceed their principal.

Effects:

- Calls `updateReward(stakingStoreIndex)` to calculate the rewards.
- Declares `uint256 principalToSend = amount`
- Subtracts the amount from the principal `currentStore.principal = currentStore.principal - amount`
- Subtracts the rewards received from the new rewards `rewardToSend = currentStore.reward - currentStore.paidOutReward;`
- Increments the `currentStore.paidOutReward` by `rewardToSend`
- Sets `currentStore.unstakingRequestTime = 0;`
- Sets `currentStore.stakingStartTime = uint64(block.timestamp);`
- Calculates the delegator’s share of the rewards `principalWalletReward = (rewardToSend * _getCurrentPrincipalWalletShareBps(stakingStoreIndex)) / 10000`
- Calculates the beneficiary’s share of the reward `beneficiaryReward = rewardToSend - principalWalletReward`

Interactions:

- safeTransfers `principalWalletReward` to the delegator's wallet (or `principalPayoutWallet`).
- safeTransfers `principalToSend` to the delegator's wallet (or `principalPayoutWallet`).
- safeTransfers the `beneficiaryReward` from the `rewardsWallet` to the beneficiary.
- Emits `Unstaked(stakingStoreIndex, principalToSend, principalWalletReward, beneficiaryReward, currentStore.principalPayoutWallet, currentStore.beneficiary)`

## Getters

### getRewardForStakingStore(uint256 stakingStoreIndex)

`getRewardForStakingStore` returns the rewards accumulated for a stake. If a staker has requested for unstaking, the rewards don't accumulate until the waiting period elapses.

- If unstaking had been requested (i.e. `currentStore.unstakingRequestTime > 0`) then `passedSeconds = currentStore.unstakingRequestTime - currentStore.stakingStartTime;`
- Else, `passedSeconds = block.timestamp - currentStore.stakingStartTime;`
- Sets `passedDays = passedSeconds / (24 * 60 * 60);`
- Returns `(rewardRatePerDay * passedDays * currentStore.principal) / 10000`

### getCurrentPrincipalWalletShareBps(uint256 stakeId)

`getCurrentPrincipalWalletShareBps` returns a uint32 of the PrincipalWalletShareBps by calling `_getCurrentPrincipalWalletShareBps(stakeId)`.
