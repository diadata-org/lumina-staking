// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./DIARewardsDistribution.sol";

 

/**
 * @title DIAExternalStaking
 * @notice This contract allows to stake tokens and earn rewards.
 */
contract DIAExternalStaking is Ownable, DIARewardsDistribution {
    using SafeERC20 for IERC20;

    /// @notice Emitted when a UnstakeDuration is changed.
    event UnstakingDurationUpdated(uint256 oldDuration, uint256 newDuration);

    /// @notice Emitted when a Principal Payout Wallet is changed.
    event PrincipalPayoutWalletUpdated(
        address oldWallet,
        address newWallet,
        uint256 stakingStoreIndex
    );

    /// @notice Structure representing staking details for a user.
    struct StakingStore {
        address beneficiary;
        address principalPayoutWallet;
        address principalUnstaker;
        uint256 principal;
        uint256 reward;
        uint256 stakingStartTime;
        uint256 unstakingRequestTime;
        uint256 principalWalletShare;

    }

    /// @notice How many tokens can be staked in total
    uint256 public stakingLimit;
    uint256 public tokensStaked;

    /// @notice How long (in seconds) for unstaking to take place
    uint256 public unstakingDuration;

    /// @notice ERC20 token used for staking.
    IERC20 public immutable STAKING_TOKEN;

    /// @notice Total number of stakers.
    uint256 public numStakers;

    /// @notice Mapping of staking index to corresponding staking store.
    mapping(uint256 => StakingStore) public stakingStores;

    /// @notice Errors
    error NotBeneficiary();
    error AlreadyRequestedUnstake();
    error UnstakingNotRequested();
    error UnstakingPeriodNotElapsed();

    error UnstakingDurationTooShort();
    error UnstakingDurationTooLong();

    error AmountBelowMinimumStake(uint256 amount);
    error AmountAboveStakingLimit(uint256 amount);

    error AmountExceedsStaked();


    error NotOwner();
    error NotPrincipalUnstaker();

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
        unstakingDuration = _unstakingDuration;
        STAKING_TOKEN = IERC20(_stakingTokenAddress);
        stakingLimit = _stakingLimit;
    }

    /**
     * @notice Allows a user to stake tokens directly.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 amount, uint256 principalWalletShare) public {
        return stakeForAddress(msg.sender, amount,principalWalletShare);
    }

    /**
     * @notice Stakes tokens on behalf of a given address.
     * @param beneficiaryAddress Address receiving the staking rewards.
     * @param amount Amount of tokens to be staked.
     */
    function stakeForAddress(
        address beneficiaryAddress,
        uint256 amount,
        uint256 principalWalletShare
    ) public {
        uint256 minimumStake = 1 * 10 ** 18; //   minimum stake of 1 tokens

        if (amount < minimumStake) {
            revert AmountBelowMinimumStake(amount);
        }
        if (amount > (stakingLimit - tokensStaked)) {
            revert AmountAboveStakingLimit(amount);
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
        newStore.principalWalletShare = principalWalletShare;
        tokensStaked += amount;
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
    function unstake(uint256 stakingStoreIndex, uint256 amount) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.unstakingRequestTime == 0) {
            revert UnstakingNotRequested();
        }

        if (amount > currentStore.principal){
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
        currentStore.reward = 0;
        uint256 principalToSend = amount;
        currentStore.principal =  currentStore.principal - amount ;
        currentStore.unstakingRequestTime =0;

        uint256 principalWalletReward = (rewardToSend * currentStore.principalWalletShare) / 100;
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
    }

    /**
     * @notice Updates the principal payout wallet for a given staking index.
     * @dev Only callable by the principal unstaker.
     * @param newWallet New wallet address for receiving the principal.
     * @param stakingStoreIndex Index of the staking store.
     */
    function updatePrincipalPayoutWallet(
        address newWallet,
        uint256 stakingStoreIndex
    ) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }
        emit PrincipalPayoutWalletUpdated(
            currentStore.principalPayoutWallet,
            newWallet,
            stakingStoreIndex
        );
        currentStore.principalPayoutWallet = newWallet;
    }

    /**
     * @notice Allows the contract owner or the current unstaker to update the unstaker.
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
        emit UnstakingDurationUpdated(unstakingDuration, newDuration);

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
        uint256 passedSeconds;
        if (currentStore.unstakingRequestTime > 0) {
            passedSeconds = currentStore.unstakingRequestTime - currentStore.stakingStartTime;
        } else {
            passedSeconds = block.timestamp - currentStore.stakingStartTime;
        }


        uint256 passedDays = passedSeconds / (24 * 60 * 60);

        uint256 accumulatedReward = currentStore.principal;
        for (uint i = 0; i < passedDays; ++i) {
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
    function updateReward(uint256 stakingStoreIndex) public {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        uint256 reward = getRewardForStakingStore(stakingStoreIndex);

 
        assert(reward >= currentStore.reward);

        currentStore.reward = reward;
    }
}
