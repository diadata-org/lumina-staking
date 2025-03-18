// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import "./DIARewardsDistribution.sol";

contract DIAExternalStaking is Ownable, DIARewardsDistribution {
    struct StakingStore {
        address beneficiary;
        uint256 principal;
        uint256 reward;
        uint256 stakingStartTime;
        uint256 unstakingRequestTime;
    }

    // How long (in seconds) for unstaking to take place
    uint256 public unstakingDuration;

    IERC20 public stakingToken;

    uint256 public numStakers;

    mapping(uint256 => StakingStore) public stakingStores;


    error NotBeneficiary();
error AlreadyRequestedUnstake();
error UnstakingNotRequested();
error UnstakingPeriodNotElapsed();

error UnstakingDurationTooShort();
error UnstakingDurationTooLong();

    constructor(
        uint256 newUnstakingDuration,
        address stakingTokenAddress,
        uint256 rewardRatePerDay
    )
        Ownable(msg.sender)
        DIARewardsDistribution(stakingTokenAddress, rewardRatePerDay)
    {
        unstakingDuration = newUnstakingDuration;
        stakingToken = IERC20(stakingTokenAddress);
    }

    // Stake
    function stake(uint256 amount) public {
        // Get the tokens into the staking contract
        require(stakingToken.transfer(address(this), amount));

        
        // Register tokens after transfer
        numStakers++;
        StakingStore storage newStore = stakingStores[numStakers];
        newStore.beneficiary = msg.sender;
        newStore.principal = amount;
        newStore.stakingStartTime = block.timestamp;
    }

    // Request to unstake, the unstake period starts now.
    // This can only be requested once.
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

    function unstake(uint256 stakingStoreIndex) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
       if (currentStore.unstakingRequestTime == 0) {
        revert UnstakingNotRequested();
    }

    if (currentStore.unstakingRequestTime + unstakingDuration > block.timestamp) {
        revert UnstakingPeriodNotElapsed();
    }

        // Ensure the reward amount is up to date
        updateReward(stakingStoreIndex);

        uint256 rewardToSend = currentStore.reward;
        currentStore.reward = 0;
        uint256 principalToSend = currentStore.principal;
        currentStore.principal = 0;

        // Send tokens to beneficiary
        stakingToken.transfer(currentStore.beneficiary, principalToSend);
        stakingToken.transferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            rewardToSend
        );
    }

    // Update unstaking duration, measured in seconds
    function setUnstakingDuration(uint256 newDuration) external onlyOwner {
         if (newDuration < 1 days) {
        revert UnstakingDurationTooShort();
    }

    if (newDuration > 20 days) {
        revert UnstakingDurationTooLong();
    }
        unstakingDuration = newDuration;
    }

    function getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) public view override returns (uint256) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        // Calculate number of full days that passed for staking store
        uint256 passedSeconds = block.timestamp - currentStore.stakingStartTime;
        uint256 passedDays = (passedSeconds / 24) * 60 * 60;

        uint256 accumulatedReward = currentStore.principal;
        for (uint256 i = 0; i < passedDays; ++i) {
            accumulatedReward += (accumulatedReward * rewardRatePerDay) / 1e10;
        }
        return accumulatedReward - currentStore.principal;
    }

    // Calculate and store reward for the staker
    function updateReward(uint256 stakingStoreIndex) public {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        uint256 reward = getRewardForStakingStore(stakingStoreIndex);
        assert(reward >= currentStore.reward);

        currentStore.reward = reward;
    }
}
