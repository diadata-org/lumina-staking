// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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

    /// @notice Emitted when daily withdrawal threshold is updated
    /// @param oldThreshold The previous threshold value
    /// @param newThreshold The new threshold value
    event DailyWithdrawalThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
    );

    /// @notice Emitted when withdrawal cap is updated
    /// @param oldCap The previous cap value in basis points
    /// @param newCap The new cap value in basis points
    event WithdrawalCapUpdated(uint256 oldCap, uint256 newCap);

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

        _internalStakeForAddress(
            msg.sender,
            beneficiaryAddress,
            amount,
            principalWalletShareBps
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
        _internalStakeForAddress(msg.sender, msg.sender, amount, 10_000);
    }

    /**
     * @notice Completes the unstaking process after the required duration
     * @dev Checks daily withdrawal limits before processing
     * @param stakingStoreIndex Index of the staking store
     * @custom:revert DailyWithdrawalLimitExceeded if withdrawal would exceed daily limit
     * @custom:revert UnstakingNotRequested if unstaking was not requested
     * @custom:revert UnstakingPeriodNotElapsed if unstaking period has not elapsed
     */
    function unstake(
        uint256 stakingStoreIndex
    ) external onlyBeneficiaryOrPayoutWallet(stakingStoreIndex) nonReentrant {
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

        uint256 rewardToSend = getRewardForStakingStore(stakingStoreIndex) -
            currentStore.paidOutReward;
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

        STAKING_TOKEN.safeTransferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            beneficiaryReward
        );
        currentStore.unstakingRequestTime = 0;
        currentStore.stakingStartTime = uint64(block.timestamp);

        emit Unstaked(
            stakingStoreIndex,
            0,
            principalWalletReward,
            beneficiaryReward,
            currentStore.principalPayoutWallet,
            currentStore.beneficiary
        );
    }

    /**
     * @notice Unstakes the principal amount immediately
     * @dev Only possible for the principal unstaker
     * @param stakingStoreIndex Index of the staking store
     * @param amount Amount of principal to unstake
     * @custom:revert NotPrincipalUnstaker if caller is not the principal unstaker
     * @custom:revert UnstakingNotRequested if unstaking was not requested
     * @custom:revert UnstakingPeriodNotElapsed if unstaking period has not elapsed
     * @custom:revert AmountExceedsStaked if amount exceeds staked principal
     */
    function unstakeOnlyPrincipalAmount(
        uint256 stakingStoreIndex,
        uint256 amount
    ) external nonReentrant {
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

        if (amount > currentStore.principal) {
            revert AmountExceedsStaked();
        }

        uint256 principalToSend = amount;
        currentStore.principal = currentStore.principal - amount;

        tokensStaked -= amount;
        currentStore.unstakingRequestTime = 0;
        // no need to reset as rewards are skip from this tx
        // currentStore.stakingStartTime = uint64(block.timestamp);

        if (principalToSend > 0) {
            // Pay out principal
            STAKING_TOKEN.safeTransfer(
                currentStore.principalPayoutWallet,
                principalToSend
            );
        }

        emit UnstakedOnlyPrincipalAmount(stakingStoreIndex, principalToSend);
    }

    /**
     * @notice Unstakes the principal amount immediately
     * @dev Only possible for the principal unstaker
     * @param stakingStoreIndex Index of the staking store
     * @param amount Amount of principal to unstake
     * @custom:revert NotPrincipalUnstaker if caller is not the principal unstaker
     * @custom:revert UnstakingNotRequested if unstaking was not requested
     * @custom:revert UnstakingPeriodNotElapsed if unstaking period has not elapsed
     * @custom:revert AmountExceedsStaked if amount exceeds staked principal
     */
    function unstakePrincipal(
        uint256 stakingStoreIndex,
        uint256 amount
    ) external nonReentrant {
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

        if (amount > currentStore.principal) {
            revert AmountExceedsStaked();
        }

        uint256 principalToSend = amount;
        currentStore.principal = currentStore.principal - amount;

        tokensStaked -= amount;

        uint256 rewardToSend = getRewardForStakingStore(stakingStoreIndex) -
            currentStore.paidOutReward;
        currentStore.paidOutReward += rewardToSend;

        currentStore.unstakingRequestTime = 0;
        currentStore.stakingStartTime = uint64(block.timestamp);

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

        if (principalToSend > 0) {
            // Pay out principal
            STAKING_TOKEN.safeTransfer(
                currentStore.principalPayoutWallet,
                principalToSend
            );
        }

        if (beneficiaryReward > 0) {
            // Send remaining reward tokens to beneficiary
            STAKING_TOKEN.safeTransferFrom(
                rewardsWallet,
                currentStore.beneficiary,
                beneficiaryReward
            );
        }

        emit Unstaked(
            stakingStoreIndex,
            principalToSend,
            principalWalletReward,
            beneficiaryReward,
            currentStore.principalPayoutWallet,
            currentStore.beneficiary
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
     * @notice Calculates the accrued reward for a given staking store
     * @dev The reward is calculated based on the number of full days passed since staking started
     * @param stakingStoreIndex The index of the staking store
     * @return The total reward accumulated so far
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
        uint256 passedDays = passedSeconds / (SECONDS_IN_A_DAY);

        // assumption: reward rate is measured in bps
        return (rewardRatePerDay * passedDays * currentStore.principal) / 10000;
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
}
