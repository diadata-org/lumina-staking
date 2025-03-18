// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract DIARewardsDistribution is Ownable {
    IERC20 public rewardsToken;

    // Reward rate per day, with 10 decimals
    uint256 public rewardRatePerDay;
    address public rewardsWallet;

    constructor(address rewardsTokenAddress, uint256 newRewardRate) {
        rewardsToken = IERC20(rewardsTokenAddress);
        rewardRatePerDay = newRewardRate;
    }

    function updateRewardRatePerDay(uint256 newRewardRate) external onlyOwner {
        rewardRatePerDay = newRewardRate;
    }

    function updateRewardsWallet(address newWalletAddress) external onlyOwner {
        rewardsWallet = newWalletAddress;
    }

    function getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) public virtual returns (uint256);
}
