// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./DIAStakingCommons.sol";
import "./DIARewardsDistribution.sol";

/**
 * @title DIAExternalStaking
 * @notice This contract allows to stake tokens and earn rewards.
 */
contract DIAExternalStaking is
    Ownable,
    DIARewardsDistribution,
    ReentrancyGuard,
    DIAStakingCommons
{
    using SafeERC20 for IERC20;

    /**
     * @dev Initializes the contract with staking parameters.
     * @param _unstakingDuration Duration in seconds required before unstaking.
     * @param _stakingTokenAddress Address of the ERC20 token used for staking.
     * @param _rewardsWallet Address of the wallet that holds rewards.This wallet should appove tokens for this contract
     * @param _rewardRatePerDay Rate at which rewards accumulate daily.
     */

    constructor(
        uint256 _unstakingDuration,
        address _stakingTokenAddress,
        address _rewardsWallet,
        uint256 _rewardRatePerDay,
        uint256 _stakingLimit
    )
        Ownable(msg.sender)
        DIARewardsDistribution(
            _stakingTokenAddress,
            _rewardsWallet,
            _rewardRatePerDay
        )
    {
        if (_stakingTokenAddress == address(0)) revert ZeroAddress();
        if (_rewardsWallet == address(0)) revert ZeroAddress();

        unstakingDuration = _unstakingDuration;
        STAKING_TOKEN = IERC20(_stakingTokenAddress);
        stakingLimit = _stakingLimit;
    }

    /**
     * @notice Allows a user to stake tokens directly.
     * @param amount The amount of tokens to stake.
     */
    function stake(
        uint256 amount,
        uint32 principalWalletShareBps
    ) public nonReentrant {
        return stakeForAddress(msg.sender, amount, principalWalletShareBps);
    }

    /**
     * @notice Stakes tokens on behalf of a given address.
     * @param beneficiaryAddress Address receiving the staking rewards.
     * @param amount Amount of tokens to be staked.
     */
    function stakeForAddress(
        address beneficiaryAddress,
        uint256 amount,
        uint32 principalWalletShareBps
    ) public {
        if (amount > (stakingLimit - tokensStaked)) {
            revert AmountAboveStakingLimit(amount);
        }

        _internalStakeForAddress(
            msg.sender,
            beneficiaryAddress,
            amount,
            principalWalletShareBps
        );
    }

    /**
     * @notice Completes the unstaking process after the required duration.
     * @param stakingStoreIndex Index of the staking store.
     */
    function unstake(
        uint256 stakingStoreIndex,
        uint256 amount
    )
        external
        nonReentrant
        onlyBeneficiaryOrPayoutWallet(stakingStoreIndex)
        checkDailyWithdrawalLimit(amount)
    {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.unstakingRequestTime == 0) {
            revert UnstakingNotRequested();
        }

        if (amount > currentStore.principal) {
            revert AmountExceedsStaked();
        }

        if (
            currentStore.unstakingRequestTime + unstakingDuration >
            block.timestamp
        ) {
            revert UnstakingPeriodNotElapsed();
        }

        // Ensure the reward amount is up to date
        updateReward(stakingStoreIndex);

        uint256 rewardToSend = currentStore.reward;
        currentStore.paidOutReward += rewardToSend;
        currentStore.reward = 0;
        uint256 principalToSend = amount;
        currentStore.principal = currentStore.principal - amount;
        tokensStaked -= amount;
        currentStore.unstakingRequestTime = 0;
        currentStore.stakingStartTime = uint64(block.timestamp);

        totalDailyWithdrawals += amount;

        uint256 principalWalletReward = (rewardToSend *
            _getCurrentPrincipalWalletShareBps(stakingStoreIndex)) / 10000;
        uint256 beneficiaryReward = rewardToSend - principalWalletReward;

        if (principalWalletReward > 0) {
            STAKING_TOKEN.safeTransferFrom(
                rewardsWallet,
                currentStore.principalPayoutWallet,
                principalWalletReward
            );
        }

        // Send principal tokens to the payout wallet
        STAKING_TOKEN.safeTransfer(
            currentStore.principalPayoutWallet,
            principalToSend
        );

        // Send reward to the beneficiary
        STAKING_TOKEN.safeTransferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            beneficiaryReward
        );
        emit Unstaked(
            currentStore.beneficiary,
            stakingStoreIndex,
            principalToSend,
            rewardToSend
        );
    }

    /**
     * @notice Calculates the accrued reward for a given staking store.
     * @dev The reward is calculated based on the number of full days passed since staking started.
     * @param stakingStoreIndex The index of the staking store.
     * @return The total reward accumulated so far.
     */
    function getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) public view override returns (uint256) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        // Calculate number of full days that passed for staking store
        uint256 passedSeconds;
        if (currentStore.unstakingRequestTime > 0) {
            passedSeconds =
                currentStore.unstakingRequestTime -
                currentStore.stakingStartTime;
        } else {
            passedSeconds = block.timestamp - currentStore.stakingStartTime;
        }

        uint256 passedDays = passedSeconds / SECONDS_IN_A_DAY;

        uint256 accumulatedReward = currentStore.principal;
        for (uint32 i = 0; i < passedDays; ++i) {
            accumulatedReward += (accumulatedReward * rewardRatePerDay) / 1e10;
        }

        return accumulatedReward - currentStore.principal;
    }

    /**
     * @notice Updates the reward amount for a given staking store.
     * @dev Ensures the reward does not decrease.
     * @param stakingStoreIndex The index of the staking store.
     * @custom:assert The newly calculated reward must be greater than or equal to the current reward.
     */
    function updateReward(uint256 stakingStoreIndex) internal {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        uint256 reward = getRewardForStakingStore(stakingStoreIndex);

        assert(reward >= currentStore.reward);

        currentStore.reward = reward;
    }
}
