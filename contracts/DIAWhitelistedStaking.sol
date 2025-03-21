// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DIARewardsDistribution.sol";

contract DIAWhitelistedStaking is Ownable, DIARewardsDistribution {
    using SafeERC20 for IERC20;
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

    // How long (in seconds) for unstaking to take place
    uint256 public unstakingDuration;

    IERC20 public stakingToken;

    uint256 public numStakers;

    mapping(address => bool) public stakingWhitelist;
    mapping(uint256 => StakingStore) public stakingStores;

    event StakerAddressAdded(address newStaker);
    event StakerAddressRemoved(address removedStaker);

    error NotBeneficiary();
    error AlreadyRequestedUnstake();
    error UnstakingNotRequested();
    error UnstakingPeriodNotElapsed();

    error UnstakingDurationTooShort();
    error UnstakingDurationTooLong();
    error AlreadyWhitelisted();

    error AmountBelowMinimumStake(uint256 amount);

    error NotWhitelisted();

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
        stakingToken = IERC20(stakingTokenAddress);
    }

    // Stake for a certain address
    function stakeForAddress(
        address beneficiaryAddress,
        uint256 amount
    ) public {
        require(stakingWhitelist[beneficiaryAddress] == true, "Beneficiary must be in staking whitelist.");
        uint256 minimumStake = 1 * 10 ** 18; //   minimum stake of 1 tokens

        if (amount < minimumStake) {
            revert AmountBelowMinimumStake(amount);
        }
        // Get the tokens into the staking contract
        stakingToken.safeTransferFrom(
            beneficiaryAddress,
            address(this),
            amount
        );

        // Register tokens after transfer
        numStakers++;
        StakingStore storage newStore = stakingStores[numStakers];
        newStore.beneficiary = beneficiaryAddress;
        newStore.principalPayoutWallet = msg.sender;
        newStore.principal = amount;
        newStore.stakingStartTime = block.timestamp;
        if (beneficiaryAddress == msg.sender) {
            newStore.principalUnstaker = msg.sender;
        }
    }

    // Stake directly for message sender
    function stake(uint256 amount) external {
        return stakeForAddress(msg.sender, amount);
    }

    // Update the wallet that will receive the principal
    // Can only be changed by the owner of the contract
    function updatePrincipalPayoutWallet(
        address newWallet,
        uint256 stakingStoreIndex
    ) external onlyOwner {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        currentStore.principalPayoutWallet = newWallet;
    }

    // Update the wallet that can unstake the principal
    // Can only be changed by the owner of the contract or the current unstaker
    function updatePrincipalUnstaker(
        address newUnstaker,
        uint256 stakingStoreIndex
    ) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.principalUnstaker == address(0)) {
            require(msg.sender == owner(), "Unstaker must be owner of the contract.");
        } else if (currentStore.principalUnstaker != msg.sender)  {
            revert("Function must be called by the principal unstaker of this stake.");
        }
        currentStore.principalUnstaker = newUnstaker;
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
        stakingToken.safeTransferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            rewardToSend
        );
        currentStore.unstakingRequestTime = 0;
        currentStore.reward = 0;
    }

    // Unstake principal immediately
    // Only possible for the principal unstaker or the global owner
    function unstakePrincipal(uint256 stakingStoreIndex) external onlyOwner {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.principalUnstaker == address(0)) {
            require(msg.sender == owner(), "Unstaker must be owner of the contract.");
        } else if (currentStore.principalUnstaker != msg.sender)  {
            revert("Function must be called by the principal unstaker of this stake.");
        }
        updateReward(stakingStoreIndex);

        uint256 rewardToSend = currentStore.reward - currentStore.paidOutReward;
        currentStore.paidOutReward += rewardToSend;

        // Send remaining reward tokens to beneficiary
        stakingToken.transferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            rewardToSend
        );
        currentStore.unstakingRequestTime = 0;

        // Pay out principal
        uint256 principalToSend = currentStore.principal;
        currentStore.principal = 0;
        stakingToken.transfer(
            currentStore.principalPayoutWallet,
            principalToSend
        );
    }

    function addWhitelistedStaker(address newStakerAddress) external onlyOwner {
        if (stakingWhitelist[newStakerAddress]) {
            revert AlreadyWhitelisted();
        }
        stakingWhitelist[newStakerAddress] = true;
        emit StakerAddressAdded(newStakerAddress);
    }

    function removeWhitelistedStaker(
        address stakerAddressToRemove
    ) external onlyOwner {
        if (!stakingWhitelist[stakerAddressToRemove]) {
            revert NotWhitelisted();
        }
        stakingWhitelist[stakerAddressToRemove] = false;
        emit StakerAddressRemoved(stakerAddressToRemove);
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
        uint256 passedDays = passedSeconds / (24 * 60 * 60);

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
