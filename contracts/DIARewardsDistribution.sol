// SPDX-License-Identifier: GPL

pragma solidity 0.8.26;

import "Ownable.sol";
import "IERC20.sol";

abstract contract DIARewardsDistribution is Ownable {
    IERC20 public rewardsToken;

    // Reward rate per day, with 10 decimals
    uint256 rewardRatePerDay;
    address rewardsWallet;

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

    function getRewardForStakingStore(uint256 stakingStoreIndex) public virtual returns(uint256);
}
