// SPDX-License-Identifier: GPL

pragma solidity 0.8.26;

import "Ownable.sol";
import "IERC20.sol";
import "DIARewardsDistribution.sol";

contract DIAWhitelistedStaking is Ownable, DIARewardsDistribution {
    struct StakingStore {
        address beneficiary;
        uint256 principal;
        uint256 reward;
        uint256 stakingStartTime;
        uint256 unstakingRequestTime;
    }

    // How long (in seconds) for unstaking to take place
    uint256 unstakingDuration;

    IERC20 public stakingToken;

    uint256 numStakers;

    mapping(address => bool) public stakingWhitelist;
    mapping(uint256 => StakingStore) public stakingStores;

    event StakerAddressAdded(address newStaker);
    event StakerAddressRemoved(address removedStaker);

    constructor(uint256 newUnstakingDuration, address stakingTokenAddress, uint256 rewardRatePerDay) 
    Ownable(msg.sender) DIARewardsDistribution(stakingTokenAddress, rewardRatePerDay) {
        unstakingDuration = newUnstakingDuration;
        stakingToken = IERC20(stakingTokenAddress);
    }

    // Stake for a certain address
    function stakeForAddress(address beneficiaryAddress, uint256 amount) public {
        // Get the tokens into the staking contract
        require(stakingToken.transferFrom(beneficiaryAddress, address(this), amount));
        // Register tokens after transfer
        numStakers++;
        StakingStore storage newStore = stakingStores[numStakers];
        newStore.beneficiary = beneficiaryAddress;
        newStore.principal = amount;
        newStore.stakingStartTime = block.timestamp;
    }

    // Stake directly for message sender
    function stake(uint256 amount) external {
        return stakeForAddress(msg.sender, amount);
    }

    // Request to unstake, the unstake period starts now.
    // This can only be requested once.
    function requestUnstake(uint256 stakingStoreIndex) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        require(msg.sender == currentStore.beneficiary, "Only beneficiary can request unstake.");
        require(currentStore.unstakingRequestTime == 0, "You can only request to unstake once.");
        currentStore.unstakingRequestTime = block.timestamp;
    }

    function unstake(uint256 stakingStoreIndex) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        require(currentStore.unstakingRequestTime > 0, "Unstaking must be requested first.");
        require(currentStore.unstakingRequestTime + unstakingDuration <= block.timestamp, "The unstaking duration must pass after unstaking has been requested.");

        // Ensure the reward amount is up to date
        updateReward(stakingStoreIndex);

        uint256 rewardToSend = currentStore.reward;
        currentStore.reward = 0;
        uint256 principalToSend = currentStore.principal;
        currentStore.principal = 0;
        
        // Send tokens to beneficiary
        stakingToken.transfer(currentStore.beneficiary, principalToSend);
        stakingToken.transferFrom(rewardsWallet, currentStore.beneficiary, rewardToSend);
    }

    function addWhitelistedStaker(address newStakerAddress) onlyOwner external {
        require(stakingWhitelist[newStakerAddress] == false);
        stakingWhitelist[newStakerAddress] = true;
        emit StakerAddressAdded(newStakerAddress);
    }

    function removeWhitelistedStaker(address stakerAddressToRemove) onlyOwner external {
        require(stakingWhitelist[stakerAddressToRemove] == true);
        stakingWhitelist[stakerAddressToRemove] = false;
        emit StakerAddressRemoved(stakerAddressToRemove);
    }

    // Update unstaking duration, measured in seconds
    function setUnstakingDuration(uint256 newDuration) onlyOwner external {
        require(newDuration >= 1 * 24 * 60 * 60, "Minimal unstaking duration is 1 day");
        require(newDuration <= 20 * 24 * 60 * 60, "Maximum unstaking duration is 20 days");
        unstakingDuration = newDuration;
    }

    function getRewardForStakingStore(uint256 stakingStoreIndex) public view override returns(uint256) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        
        // Calculate number of full days that passed for staking store
        uint256 passedSeconds = block.timestamp - currentStore.stakingStartTime;
        uint256 passedDays = passedSeconds / 24 * 60 * 60;

        return rewardRatePerDay * passedDays;
    }
    
    // Calculate and store reward for the staker
    function updateReward(uint256 stakingStoreIndex) public {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        uint256 reward = getRewardForStakingStore(stakingStoreIndex);
        assert(reward >= currentStore.reward);

        currentStore.reward = reward;
    }
}
