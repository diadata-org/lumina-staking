// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./DIARewardsDistribution.sol";

/**
 * @title DIAWhitelistedStaking
 * @notice This contract allows whitelisted addresses to stake tokens and earn rewards.
 */
contract DIAWhitelistedStaking is Ownable, DIARewardsDistribution ,ReentrancyGuard{
    using SafeERC20 for IERC20;

    /// @notice Structure representing staking details for a user.
    struct StakingStore {
        address beneficiary;
        address principalPayoutWallet;
        address principalUnstaker;
        uint256 principal;
        uint256 reward;
        uint256 paidOutReward;
        uint256 stakingStartTime;
        uint256 unstakingRequestTime;
    }

    /// @notice How long (in seconds) for unstaking to take place
    uint256 public unstakingDuration;

    /// @notice ERC20 token used for staking.
    IERC20 public immutable STAKING_TOKEN;

    /// @notice Total number of stakers.
    uint256 public numStakers;

    /// @notice Mapping of whitelisted addresses for staking.
    mapping(address => bool) public stakingWhitelist;

    /// @notice Mapping of staking index to corresponding staking store.
    mapping(uint256 => StakingStore) public stakingStores;

    /// @notice Emitted when a new staker is added to the whitelist.
    event StakerAddressAdded(address newStaker);

    /// @notice Emitted when a staker is removed from the whitelist.
    event StakerAddressRemoved(address removedStaker);

    /// @notice Errors
    error NotBeneficiary();
    error AlreadyRequestedUnstake();
    error UnstakingNotRequested();
    error UnstakingPeriodNotElapsed();

    error UnstakingDurationTooShort();
    error UnstakingDurationTooLong();
    error AlreadyWhitelisted();

    error AmountBelowMinimumStake(uint256 amount);

    error NotWhitelisted();

    error NotOwner();
    error NotPrincipalUnstaker();

    /**
     * @dev Initializes the contract with staking parameters.
     * @param newUnstakingDuration Duration in seconds required before unstaking.
     * @param stakingTokenAddress Address of the ERC20 token used for staking.
     * @param rewardsWallet Address of the wallet that holds rewards.This wallet should appove tokens for this contract
     * @param rewardRatePerDay Rate at which rewards accumulate daily.
     */

    constructor(
        uint256 newUnstakingDuration,
        address stakingTokenAddress,
        address rewardsWallet,
        uint256 rewardRatePerDay
    )
        Ownable(msg.sender)
        DIARewardsDistribution(
            stakingTokenAddress,
            rewardsWallet,
            rewardRatePerDay
        )
    {
        unstakingDuration = newUnstakingDuration;
        STAKING_TOKEN = IERC20(stakingTokenAddress);
    }

    /**
     * @notice Stakes tokens on behalf of a given address.
     * @param beneficiaryAddress Address receiving the staking rewards.
     * @param amount Amount of tokens to be staked.
     */
    function stakeForAddress(
        address beneficiaryAddress,
        uint256 amount
    ) public {
        if (!stakingWhitelist[beneficiaryAddress]) {
            revert NotWhitelisted();
        }
        uint256 minimumStake = 1 * 10 ** 18; //   minimum stake of 1 tokens

        if (amount < minimumStake) {
            revert AmountBelowMinimumStake(amount);
        }
        // Get the tokens into the staking contract
        STAKING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        // Register tokens after transfer
        numStakers++;
        StakingStore storage newStore = stakingStores[numStakers];
        newStore.beneficiary = beneficiaryAddress;
        newStore.principalPayoutWallet = msg.sender;
        newStore.principal = amount;
        newStore.stakingStartTime = block.timestamp;
        newStore.principalUnstaker = msg.sender;
    }

    /**
     * @notice Allows a user to stake tokens directly.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 amount) external {
        return stakeForAddress(msg.sender, amount);
    }

    /**
     * @notice Updates the principal payout wallet for a given staking index.
     * @dev Only callable by the contract owner.
     * @param newWallet New wallet address for receiving the principal.
     * @param stakingStoreIndex Index of the staking store.
     */
    function updatePrincipalPayoutWallet(
        address newWallet,
        uint256 stakingStoreIndex
    ) external onlyOwner {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        currentStore.principalPayoutWallet = newWallet;
    }

    /**
     * @notice Allows the current unstaker to update the unstaker.
     * @param newUnstaker New address allowed to unstake the principal.
     * @param stakingStoreIndex Index of the staking store.
     */
    function updatePrincipalUnstaker(
        address newUnstaker,
        uint256 stakingStoreIndex
    ) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }
        currentStore.principalUnstaker = newUnstaker;
    }

    /**
     * @notice Requests unstaking, starting the waiting period.
     * @dev Can only be called by the beneficiary.
     * @param stakingStoreIndex Index of the staking store.
     */
    function requestUnstake(uint256 stakingStoreIndex) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (msg.sender != currentStore.beneficiary) {
            revert NotBeneficiary();
        }

        if (currentStore.unstakingRequestTime != 0) {
            revert AlreadyRequestedUnstake();
        }
        currentStore.unstakingRequestTime = block.timestamp;
    }

    /**
     * @notice Completes the unstaking process after the required duration.
     * @param stakingStoreIndex Index of the staking store.
     */
    function unstake(uint256 stakingStoreIndex) external {
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

        // Ensure the reward amount is up to date
        updateReward(stakingStoreIndex);

        uint256 rewardToSend = currentStore.reward - currentStore.paidOutReward;
        currentStore.paidOutReward += rewardToSend;

        // Send tokens to beneficiary
        STAKING_TOKEN.safeTransferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            rewardToSend
        );
        currentStore.unstakingRequestTime = 0;
        currentStore.reward = 0;
    }

    /**
     * @notice Unstakes the principal amount immediately.
     * @dev Only possible for the principal unstaker or the global owner
     * @param stakingStoreIndex Index of the staking store.
     */
    function unstakePrincipal(uint256 stakingStoreIndex) external nonReentrant() {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }
        updateReward(stakingStoreIndex);

        uint256 rewardToSend = currentStore.reward - currentStore.paidOutReward;
        currentStore.paidOutReward += rewardToSend;

       
        currentStore.unstakingRequestTime = 0;

        // Pay out principal
        uint256 principalToSend = currentStore.principal;
        currentStore.principal = 0;
        STAKING_TOKEN.transfer(
            currentStore.principalPayoutWallet,
            principalToSend
        );
         // Send remaining reward tokens to beneficiary
        STAKING_TOKEN.transferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            rewardToSend
        );
    }

    /**
     * @notice Adds an address to the whitelist for staking.
     * @dev Only callable by the contract owner.
     * @param newStakerAddress The address to be whitelisted.
     * @custom:revert AlreadyWhitelisted() if the address is already whitelisted.
     * @custom:event Emits `StakerAddressAdded` on success.
     */

    function addWhitelistedStaker(address newStakerAddress) external onlyOwner {
        if (stakingWhitelist[newStakerAddress]) {
            revert AlreadyWhitelisted();
        }
        stakingWhitelist[newStakerAddress] = true;
        emit StakerAddressAdded(newStakerAddress);
    }

    /**
     * @notice Removes an address from the staking whitelist.
     * @dev Only callable by the contract owner.
     * @param stakerAddressToRemove The address to remove from the whitelist.
     * @custom:revert NotWhitelisted() if the address is not currently whitelisted.
     * @custom:event Emits `StakerAddressRemoved` on success.
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
     * @notice Updates the duration required before unstaking can be completed.
     * @dev Only callable by the contract owner.
     * @param newDuration The new unstaking duration, in seconds.
     * @custom:revert UnstakingDurationTooShort() if the new duration is less than 1 day.
     * @custom:revert UnstakingDurationTooLong() if the new duration exceeds 20 days.
     */
    function setUnstakingDuration(uint256 newDuration) external onlyOwner {
        if (newDuration < 1 days) {
            revert UnstakingDurationTooShort();
        }

        if (newDuration > 20 days) {
            revert UnstakingDurationTooLong();
        }
        unstakingDuration = newDuration;
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
        uint256 passedSeconds = block.timestamp - currentStore.stakingStartTime;
        uint256 passedDays = passedSeconds / (24 * 60 * 60);

        

        return rewardRatePerDay * passedDays;
    }

    /**
     * @notice Updates the reward amount for a given staking store.
     * @dev Ensures the reward does not decrease.
     * @param stakingStoreIndex The index of the staking store.
     * @custom:assert The newly calculated reward must be greater than or equal to the current reward.
     */
    function updateReward(uint256 stakingStoreIndex) public {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        uint256 reward = getRewardForStakingStore(stakingStoreIndex);
        assert(reward >= currentStore.reward);

        currentStore.reward = reward;
    }
}
