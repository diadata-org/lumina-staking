// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract DIARewardsDistribution is Ownable {
    IERC20 public immutable REWARDS_TOKEN;

    // Reward rate per day, with 10 decimals
    uint256 public rewardRatePerDay;
    address public rewardsWallet;

    error InvalidAddress();

    event RewardRateUpdated(uint256 oldRewardRate, uint256 newRewardRate);
    event RewardsWalletUpdated(address oldWallet, address newWallet);

    constructor(
        address rewardsTokenAddress,
        address newRewardsWallet,
        uint256 newRewardRate
    ) {
        REWARDS_TOKEN = IERC20(rewardsTokenAddress);
        rewardRatePerDay = newRewardRate;
        rewardsWallet = newRewardsWallet;
    }

    function updateRewardRatePerDay(uint256 newRewardRate) external onlyOwner {
        emit RewardRateUpdated(rewardRatePerDay, newRewardRate);

        rewardRatePerDay = newRewardRate;
    }

    function updateRewardsWallet(address newWalletAddress) external onlyOwner {
        if (newWalletAddress == address(0)) {
            revert InvalidAddress();
        }
        emit RewardsWalletUpdated(rewardsWallet, newWalletAddress);

        rewardsWallet = newWalletAddress;
    }

    function getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) public virtual returns (uint256);
}
