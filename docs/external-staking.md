# DIAExternalStaking Pool

[`DIAExternalStaking.sol`](../contracts/DIAExternalStaking.sol) is a permissionless staking pool designed to allow participation from anyone who can either simply stake DIA tokens or delegate their stake to a beneficiary. The beneficiary can be a node operator within the Distributed Feeder Network (DFN), a DAO organization, or any other community.

The rewards are distributed based on the staker's share of the total pool. The contract supports splitting the rewards in case of delegation between the staker (or delegator) and beneficiary, allowing for a flexible reward distribution.

Features:

- Each stake is represented by “pool shares”. The share represents their principal and accrued rewards.
- Rewards are distributed based on each staker's share of the total pool where
- Users can have multiple stakes, each tracked separately with different roles and reward splits.
- Support for 3 types of roles:
  - `Beneficiary`
  - `PrincipalPayoutWallet` (can be the delegator itself)
  - `PrincipalUnstaker` (can be the delegator itself)
- The contract enforces a daily withdrawal cap (as a percentage of the pool) when the pool size exceeds a configurable threshold.

Staking information is stored in a struct:

```solidity
    struct ExternalStakingStore {
        address beneficiary;
        address principalPayoutWallet;
        address principalUnstaker;
        uint256 principal;
        uint256 poolShares;
        uint64 stakingStartTime;
        uint64 unstakingRequestTime;
        uint32 principalWalletShareBps;
    }
```

# Formulas

For a given user's stake `ExternalStakingStore storage store = stakingStores[stakingStoreIndex]`, the following formulas apply:

### totalPoolSize

`totalPoolSize += amount;`

### totalShareAmount

`totalShareAmount += poolSharesGiven` where `poolSharesGiven = (amount * totalShareAmount) / totalPoolSize`

### claimableTokens

`claimableTokens = (store.poolShares * totalPoolSize) / totalShareAmount`

### principalWalletReward

`principalWalletReward = (fullReward * store.principalWalletShareBps) / 10000` where `fullReward = claimableTokens - store.principal;`

### beneficiaryWalletReward

`beneficiaryWalletReward = fullReward - principalWalletReward`

# Methods

## Staking

### stakeForAddress(address beneficiaryAddress, uint256 amount, uint32 principalWalletShareBps)

`stakeForAddress` delegates stake to the beneficiary and sets the reward share % for the delegator (or the principalPayoutWallet). The remaining % goes to the beneficiary.

Interactions:

- Calls `_stake(beneficiaryAddress, amount, principalWalletShareBps, msg.sender)`

### stake(uint256 amount, uint32 principalWalletShareBps)

`stake` deposits an amount to the _msg.sender's_ balance and sets their rewards share %.

Interactions:

- Calls `_stake(msg.sender, amount, principalWalletShareBps, msg.sender)`

## Unstaking

### requestUnstake(uint256 stakingStoreIndex)

`requestUnstake` makes a request to unstake the principal and claim the rewards.

Checks:

- Caller is either the beneficiary or the delegator (`onlyBeneficiaryOrPayoutWallet` modifier).
- Caller has no active request `currentStore.unstakingRequestTime != 0`

Effects:

- Sets the request time to block.timestamp `currentStore.unstakingRequestTime = uint64(block.timestamp)`

Interactions:

- Emits `UnstakeRequested(msg.sender, stakingStoreIndex)`

### unstake(uint256 stakingStoreIndex, uint256 amount)

`unstake` sends rewards accumulated to the beneficiary & delegator. It also transfers the principal to the delegator. Requires a withdrawal request submission via `requestUnstake(uint256 stakingStoreIndex)`.

Checks:

- Caller is either the beneficiary or the delegator (`onlyBeneficiaryOrPayoutWallet` modifier).
- Amount doesn't exceed the daily withdrawal limit (`checkDailyWithdrawalLimit` modifier).
- Caller made an unstake request.
- Amount doesn't exceed the staked principal.
- Unstake (or waiting) period has elapsed.
- Amount is less than or equal to the total value of the staker’s share `amount > currentAmountOfPool`

Effects:

- Calculates the staker’s share of the pool based on the requested amount `poolSharesUnstakeAmount = (currentStore.poolShares * amount) / currentAmountOfPool;`
- Calculates the principal to unstake based on the requested amount `principalUnstakeAmount = (currentStore.principal * amount) /  currentAmountOfPool;`
- Calculates the rewards to unstake based on the requested amount `rewardUnstakeAmount = amount - principalUnstakeAmount;`
- Declares `uint256 principalToSend = principalUnstakeAmount;`
- Declares `uint256 rewardToSend = currentStore.reward;`.
- Decrements `currentStore.principal` by `principalUnstakeAmount;`
- Decrements the `tokensStaked` in the pool by `principalUnstakeAmount`.
- Decrements the `currentStore.poolShares` by `poolSharesUnstakeAmount`.
- Sets `currentStore.unstakingRequestTime = 0;`.
- Sets `currentStore.stakingStartTime = uint64(block.timestamp);`.
- Increments `totalDailyWithdrawals` by amount.
- Decrements the `totalPoolSize` by `amount`
- Decrements the `totalShareAmount` by `poolSharesUnstakeAmount`
- Calculates the reward share of the delegator (`principalWalletReward`) based on the `PrincipalWalletShareBps`
- Calculates the reward share of the beneficiary `beneficiaryReward = rewardToSend - principalWalletReward;`

Interactions:

- safeTransfers the `principalWalletReward` to the delegator.
- safeTransfers the amount to the delegator.
- safeTransfers the `beneficiaryReward` to the beneficiary.
- Emits Unstaked(stakingStoreIndex, principalToSend, principalWalletReward, beneficiaryReward, currentStore.principalPayoutWallet, currentStore.beneficiary)

### addRewardToPool(uint256 amount)

`addRewardToPool` adds tokens to the pool to increase the reward share.

Interactions:

- safeTransfers the amount from the `msg.sender` to the pool (address(this))
- Increases the `totalPoolSize` by amount
- Emits RewardAdded(amount, msg.sender);

## Setters

### setUnstakingDuration(uint256 newDuration)

`setUnstakingDuration` sets the waiting duration that must elapse before the staker is able to call `unstake`

Checks:

- newDuration within [1, 20] days

Effects:

- Emits `UnstakingDurationUpdated(unstakingDuration, newDuration)`
- Sets `unstakingDuration = newDuration`

### setWithdrawalCapBps(uint256 newBps)

`setWithdrawalCapBps` sets the maximum percentage % of the pool that can be withdrawn in a single day when `totalPoolSize > dailyWithdrawalThreshold`.

Checks:

- newBps is no more than 100%

Effects:

- Declares `uint256 oldCap = withdrawalCapBps`
- Sets `withdrawalCapBps = newBps`
- Emits `WithdrawalCapUpdated(oldCap, newBps)`

### setDailyWithdrawalThreshold(uint256 newThreshold)

`setDailyWithdrawalThreshold` sets the minimum pool size at which the daily withdrawal cap is enforced.

Checks:

- newThreshold <= 0

Effects:

- Declares `uint256 oldThreshold = dailyWithdrawalThreshold`
- Sets `dailyWithdrawalThreshold = newThreshold`
- Emits `DailyWithdrawalThresholdUpdated(oldThreshold, newThreshold)`

## Updaters

### updatePrincipalPayoutWallet(address newWallet, uint256 stakingStoreIndex)

`updatePrincipalPayoutWallet` assigns a new wallet address to the principalPayoutWallet for whom the principal is transferred to and has the right to `requestUnstake` and `unstake`.

Checks:

- newWallet is not the zero address

Effects:

- Declares `ExternalStakingStore currentStore = stakingStores[stakingStoreIndex]`
- Declares `address oldWallet = currentStore.principalPayoutWallet`
- Updates the wallet address `currentStore.principalPayoutWallet = newWallet`
- Checks if the msg.sender is the delegator. Reverts if `currentStore.principalUnstaker != msg.sender`.

Interactions:

- Calls ` _removeStakingIndexFromAddressMapping(oldWallet, stakingStoreIndex, stakingIndicesByPayoutWallet)`
- Maps the newWallet to the current stakingStoreIndex `stakingIndicesByPayoutWallet[newWallet].push(stakingStoreIndex)`
- Emits PrincipalPayoutWalletUpdated(oldWallet, newWallet, stakingStoreIndex)

### updatePrincipalUnstaker(address newUnstaker, uint256 stakingStoreIndex)

`updatePrincipalUnstaker` assigns a new wallet address to the principalUnstaker that can invoke `updatePrincipalPayoutWallet`.

Checks:

- newUnstaker is not the zero address
- Checks if the msg.sender is the delegator. Reverts if `currentStore.principalUnstaker != msg.sender`.

Effects:

- Updates the address of the principalUnstaker `currentStore.principalUnstaker = newUnstaker`

### requestPrincipalWalletShareUpdate(uint256 stakeId, uint32 newShareBps)

`requestPrincipalWalletShareUpdate` creates a request for updating the rewards share % for the delegator (or the principalPayoutWallet). The new share % will be used after a SHARE_UPDATE_GRACE_PERIOD has elapsed from the time of the request (see `_getCurrentPrincipalWalletShareBps`).

Checks:

- Caller is the stake’s principalUnstaker. Reverts if `msg.sender != stakingStores[stakingStoreIndex].principalUnstaker`.
- newShareBps is less than or equal to 100%

Effects:

- Stores the update info in `PendingShareUpdate(newShareBps, block.timestamp)` struct variable and maps it to the `stakeId`

Interactions:

- Emits `PrincipalWalletShareUpdateRequested(stakeId, newShareBps, block.timestamp)`

## Getters

### getStakingIndicesByBeneficiary(address beneficiary)

`getStakingIndicesByBeneficiary` returns a uint256[] of the staking indices mapped to the beneficiary.

### getStakingIndicesByPrincipalUnstaker(address unstaker)

`getStakingIndicesByPrincipalUnstaker` returns a uint256[] of the staking indices mapped to the principalUnstaker.

### getStakingIndicesByPayoutWallet(address payoutWallet)

`getStakingIndicesByPayoutWallet` returns a uint256[] of the staking indices mapped to the principalPayoutWallet.

### getCurrentPrincipalWalletShareBps(uint256 stakeId)

`getCurrentPrincipalWalletShareBps` returns a uint32 of the PrincipalWalletShareBps by calling `_getCurrentPrincipalWalletShareBps(stakeId)`.

### getRewardForStakingStore(uint256 stakingStoreIndex)

`getRewardForStakingStore` returns the delegator and beneficiary’s rewards accumulated for a given stake.

- Declares `ExternalStakingStore storage store = stakingStores[stakingStoreIndex]`
- Calculates `claimableTokens = (store.poolShares * totalPoolSize) / totalShareAmount`
- Subtracts store.principal from the claimableTokens to get the fullRewards
- Calculates the delegator’s share of the reward `principalWalletReward = (fullReward * store.principalWalletShareBps) / 10000`
- Returns the delegator and beneficiary’s share of the rewards `return (principalWalletReward, fullReward - principalWalletReward)`
