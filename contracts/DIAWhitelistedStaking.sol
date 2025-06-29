// SPDX-License-Identifier: GPL
pragma solidity 0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DIAStakingCommons.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./DIARewardsDistribution.sol";

/**
 * @title DIAWhitelistedStaking
 * @notice This contract allows whitelisted addresses to stake tokens and earn rewards.
 */
contract DIAWhitelistedStaking is
    Ownable,
    DIARewardsDistribution,
    ReentrancyGuard,
    DIAStakingCommons
{
    using SafeERC20 for IERC20;

    /// @notice Mapping of whitelisted addresses for staking
    /// @dev Maps address to boolean indicating if address is whitelisted
    mapping(address => bool) public stakingWhitelist;

    /// @notice Emitted when a new staker is added to the whitelist
    /// @param newStaker The address that was added to the whitelist
    event StakerAddressAdded(address newStaker);

    /// @notice Emitted when a staker is removed from the whitelist
    /// @param removedStaker The address that was removed from the whitelist
    event StakerAddressRemoved(address removedStaker);

    /// @notice Emitted when unstaking only principal amount
    /// @param stakingStoreIndex Index of the staking store
    /// @param amount Amount of principal unstaked
    event UnstakedOnlyPrincipalAmount(
        uint256 stakingStoreIndex,
        uint256 amount
    );

    /// @notice Errors
    error AlreadyWhitelisted();

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
        uint256 _rewardRatePerDay
    )
        Ownable(msg.sender)
        DIARewardsDistribution(_rewardsWallet, _rewardRatePerDay)
    {
        if (_stakingTokenAddress == address(0)) revert ZeroAddress();

        if (_unstakingDuration < 1 days) {
            revert UnstakingDurationTooShort();
        }

        if (_unstakingDuration > 20 days) {
            revert UnstakingDurationTooLong();
        }

        unstakingDuration = _unstakingDuration;
        STAKING_TOKEN = IERC20(_stakingTokenAddress);
    }

    /**
     * @notice Stakes tokens on behalf of a given address
     * @param beneficiaryAddress Address receiving the staking rewards
     * @param amount Amount of tokens to be staked
     * @param principalWalletShareBps Share of rewards going to principal wallet in basis points
     * @custom:revert NotWhitelisted if beneficiary is not whitelisted
     */
    function stakeForAddress(
        address beneficiaryAddress,
        uint256 amount,
        uint32 principalWalletShareBps
    ) public nonReentrant {
        if (!stakingWhitelist[msg.sender]) {
            revert NotWhitelisted();
        }

        if (!stakingWhitelist[beneficiaryAddress]) {
            revert NotWhitelisted();
        }

        _updateRewardAccumulator();

        _internalStakeForAddress(
            msg.sender,
            beneficiaryAddress,
            amount,
            principalWalletShareBps,
            rewardAccumulator
        );
    }

    /**
     * @notice Allows a user to stake tokens directly
     * @param amount The amount of tokens to stake
     * @custom:revert NotWhitelisted if caller is not whitelisted
     */
    function stake(uint256 amount) external nonReentrant {
        if (!stakingWhitelist[msg.sender]) {
            revert NotWhitelisted();
        }

        _updateRewardAccumulator();

        _internalStakeForAddress(
            msg.sender,
            msg.sender,
            amount,
            10_000,
            rewardAccumulator
        );
    }

    /**
     * @notice Completes the unstaking process after the required duration
     * @dev Checks daily withdrawal limits before processing
     * @param stakingStoreIndex Index of the staking store
     * @custom:revert DailyWithdrawalLimitExceeded if withdrawal would exceed daily limit
     * @custom:revert UnstakingNotRequested if unstaking was not requested
     * @custom:revert UnstakingPeriodNotElapsed if unstaking period has not elapsed
     */
    function claim(
        uint256 stakingStoreIndex
    ) external onlyBeneficiaryOrPayoutWallet(stakingStoreIndex) nonReentrant {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        uint256 rewardToSend;

        if (currentStore.pendingRewards != 0) {
            rewardToSend = currentStore.pendingRewards;
            currentStore.isClaimable = false;
        } else if (
            (currentStore.pendingRewards == 0 && !currentStore.isClaimable) ||
            currentStore.unstakingRequestTime != 0
        ) {
            rewardToSend = 0;
        } else {
            rewardToSend = _getRewardForStakingStore(stakingStoreIndex);
        }

        currentStore.paidOutReward += rewardToSend;

        uint256 principalWalletReward = (rewardToSend *
            _getCurrentPrincipalWalletShareBps(stakingStoreIndex)) / 10000;
        uint256 beneficiaryReward = rewardToSend - principalWalletReward;

        if (principalWalletReward > 0) {
            // Send tokens to delegator
            STAKING_TOKEN.safeTransferFrom(
                rewardsWallet,
                currentStore.principalPayoutWallet,
                principalWalletReward
            );
        }

        if (beneficiaryReward > 0) {
            STAKING_TOKEN.safeTransferFrom(
                rewardsWallet,
                currentStore.beneficiary,
                beneficiaryReward
            );
        }

        currentStore.pendingRewards = 0;
        currentStore.lastClaimTime = uint64(block.timestamp);

        emit Claimed(
            stakingStoreIndex,
            0,
            principalWalletReward,
            beneficiaryReward,
            currentStore.principalPayoutWallet,
            currentStore.beneficiary
        );
    }

    /**
     * @notice Requests unstaking, starting the waiting period.
     * @dev Can only be called by the beneficiary.
     * @param stakingStoreIndex Index of the staking store.
     */
    function requestUnstake(
        uint256 stakingStoreIndex
    ) external nonReentrant onlyBeneficiaryOrPayoutWallet(stakingStoreIndex) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        if (currentStore.unstakingRequestTime != 0) {
            revert AlreadyRequestedUnstake();
        }

        if (currentStore.principal == 0) {
            revert NoStakedPrincipal();
        }

        if (currentStore.pendingRewards == 0 && currentStore.isClaimable) {
            uint256 pendingRewards = _getRewardForStakingStore(
                stakingStoreIndex
            );
            currentStore.pendingRewards = pendingRewards;
        }

        currentStore.unstakingRequestTime = uint64(block.timestamp);
        emit UnstakeRequested(msg.sender, stakingStoreIndex);
    }

    /**
     * @notice Unstakes the principal amount immediately
     * @dev Only possible for the principal unstaker
     * @param stakingStoreIndex Index of the staking store
     * @custom:revert NotPrincipalUnstaker if caller is not the principal unstaker
     * @custom:revert UnstakingNotRequested if unstaking was not requested
     * @custom:revert UnstakingPeriodNotElapsed if unstaking period has not elapsed
     * @custom:revert AmountExceedsStaked if amount exceeds staked principal
     */
    function unstake(uint256 stakingStoreIndex) external nonReentrant {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        if (currentStore.unstakingRequestTime == 0) {
            revert UnstakingNotRequested();
        }
        if (
            currentStore.unstakingRequestTime + unstakingDuration >
            block.timestamp
        ) {
            revert UnstakingPeriodNotElapsed();
        }

        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }

        uint256 principalToSend = currentStore.principal;
        tokensStaked -= principalToSend;

        currentStore.unstakingRequestTime = 0;
        currentStore.principal = 0;

        if (principalToSend > 0) {
            // Pay out principal
            STAKING_TOKEN.safeTransfer(
                currentStore.principalPayoutWallet,
                principalToSend
            );
        }

        emit Unstaked(
            stakingStoreIndex,
            principalToSend,
            currentStore.principalPayoutWallet
        );
    }

    /**
     * @notice Adds an address to the whitelist for staking
     * @dev Only callable by the contract owner
     * @param newStakerAddress The address to be whitelisted
     * @custom:revert AlreadyWhitelisted if the address is already whitelisted
     * @custom:event Emits StakerAddressAdded on success
     */
    function addWhitelistedStaker(address newStakerAddress) external onlyOwner {
        if (stakingWhitelist[newStakerAddress]) {
            revert AlreadyWhitelisted();
        }
        stakingWhitelist[newStakerAddress] = true;
        emit StakerAddressAdded(newStakerAddress);
    }

    /**
     * @notice Removes an address from the staking whitelist
     * @dev Only callable by the contract owner
     * @param stakerAddressToRemove The address to remove from the whitelist
     * @custom:revert NotWhitelisted if the address is not currently whitelisted
     * @custom:event Emits StakerAddressRemoved on success
     */
    function removeWhitelistedStaker(
        address stakerAddressToRemove
    ) external onlyOwner {
        if (!stakingWhitelist[stakerAddressToRemove]) {
            revert NotWhitelisted();
        }
        stakingWhitelist[stakerAddressToRemove] = false;
        emit StakerAddressRemoved(stakerAddressToRemove);
    }

    /**
     * @notice Get the current principal wallet share basis points for a stake
     * @param stakeId The ID of the stake to check
     * @return The current principal wallet share in basis points
     */
    function getCurrentPrincipalWalletShareBps(
        uint256 stakeId
    ) public view returns (uint32) {
        return _getCurrentPrincipalWalletShareBps(stakeId);
    }

    /**
     * @notice Updates the maximum number of stakes allowed per beneficiary
     * @param newLimit New maximum number of stakes per beneficiary
     * @custom:revert InvalidStakesPerBeneficiaryLimit if new limit is zero
     */
    function setMaxStakesPerBeneficiary(uint256 newLimit) external onlyOwner {
        if (newLimit == 0) revert InvalidStakesPerBeneficiaryLimit();
        uint256 oldLimit = maxStakesPerBeneficiary;
        maxStakesPerBeneficiary = newLimit;
        emit MaxStakesPerBeneficiaryUpdated(oldLimit, newLimit);
    }

    /**
     * @notice Gets the number of stakes for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Number of stakes for the beneficiary
     */
    function getStakesCountForBeneficiary(
        address beneficiary
    ) external view returns (uint256) {
        return stakingIndicesByBeneficiary[beneficiary].length;
    }

    /**
     * @notice Calculates the accrued reward for a given staking store
     * @dev The reward is calculated based on the number of full days passed since staking started
     * @param stakingStoreIndex The index of the staking store
     * @return The total reward accumulated so far
     */
    function _getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) internal returns (uint256) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        _updateRewardAccumulator();

        uint256 stakerDelta = rewardAccumulator -
            currentStore.rewardAccumulator;
        currentStore.rewardAccumulator += stakerDelta;

        uint256 stakerReward = (stakerDelta * currentStore.principal) / 10000;

        return stakerReward;
    }

    /**
     * @notice Updates the reward accumulator
     * @dev Updates the reward accumulator based on the daysElapsed since rewardLastUpdateTime
     * @dev Only updates if at least one full day has elapsed
     */
    function _updateRewardAccumulator() internal {
        uint256 daysElapsed = (block.timestamp - rewardLastUpdateTime) /
            SECONDS_IN_A_DAY;

        if (daysElapsed > 0) {
            uint256 rewardsAccrued = (rewardRatePerDay * daysElapsed);
            rewardAccumulator += rewardsAccrued;
            rewardLastUpdateTime += SECONDS_IN_A_DAY * daysElapsed;
        }
    }

    /**
     * @notice Calculates the reward accumulator for a given staking store
     * @dev View function that does not update the global rewardAccumulator
     * @return The reward accumulator
     */
    function _getCurrentRewardAccumulator() internal view returns (uint256) {
        uint256 daysElapsed = (block.timestamp - rewardLastUpdateTime) /
            SECONDS_IN_A_DAY;
        uint256 rewardsAccrued = (rewardRatePerDay * daysElapsed);
        uint256 rewardAccumulator_ = rewardAccumulator + rewardsAccrued;

        return rewardAccumulator_;
    }

    /**
     * @notice Calculates the total rewards for a given staking store
     * @param stakingStoreIndex The index of the staking store
     * @return The total rewards accumulated
     */
    function getTotalRewards(
        uint256 stakingStoreIndex
    ) public view returns (uint256) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        uint256 stakerTotalRewards;

        if (currentStore.pendingRewards != 0) {
            stakerTotalRewards =
                currentStore.paidOutReward +
                currentStore.pendingRewards;
        } else if (
            (currentStore.pendingRewards == 0 && !currentStore.isClaimable) ||
            currentStore.unstakingRequestTime != 0
        ) {
            stakerTotalRewards = currentStore.paidOutReward;
        } else {
            uint256 rewardAccumulator_ = _getCurrentRewardAccumulator();

            uint256 stakerDelta = rewardAccumulator_ -
                currentStore.rewardAccumulator;
            uint256 currentRewardAccumulator = (stakerDelta +
                currentStore.rewardAccumulator) -
                currentStore.initialRewardAccumulator;

            stakerTotalRewards =
                (currentRewardAccumulator * currentStore.principal) /
                10000;
        }

        return stakerTotalRewards;
    }

    /**
     * @notice Calculates the remaining rewards for a given staking store
     * @param stakingStoreIndex The index of the staking store
     * @return The remaining rewards
     */
    function getRemainingRewards(
        uint256 stakingStoreIndex
    ) external view returns (uint256) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        uint256 stakerRemainingRewards;

        if (currentStore.pendingRewards != 0) {
            stakerRemainingRewards = currentStore.pendingRewards;
        } else if (
            (currentStore.pendingRewards == 0 && !currentStore.isClaimable) ||
            currentStore.unstakingRequestTime != 0
        ) {
            stakerRemainingRewards = 0;
        } else {
            uint256 rewardAccumulator_ = _getCurrentRewardAccumulator();

            uint256 stakerDelta = rewardAccumulator_ -
                currentStore.rewardAccumulator;
            stakerRemainingRewards =
                (stakerDelta * currentStore.principal) /
                10000;
        }

        return stakerRemainingRewards;
    }
}
