// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./StakingErrorsAndEvents.sol";
/**
 * @title DIARewardsDistribution
 * @notice Abstract contract for managing token rewards distribution
 * @dev Provides base functionality for reward rate and wallet management
 */
abstract contract DIARewardsDistribution is Ownable {
    // Reward rate per day, with 10 decimals
    uint256 public rewardRatePerDay;

    /// @notice Address of the wallet that holds rewards
    /// @dev This wallet must approve tokens for the staking contract
    address public rewardsWallet;

    /// @notice Accumulated rewards for all staking stores
    uint256 public rewardAccumulator;

    /// @notice Last time the _rewardAccumulator was updated
    uint256 public rewardLastUpdateTime;

    /// @notice Error thrown when an invalid address is provided
    error InvalidAddress();

    /// @notice Error thrown when reward rate exceeds maximum allowed
    error InvalidRewardRate(uint256 newRate);

    /// @notice Emitted when reward rate is updated
    /// @param oldRewardRate The previous reward rate
    /// @param newRewardRate The new reward rate
    event RewardRateUpdated(uint256 oldRewardRate, uint256 newRewardRate);

    /// @notice Emitted when rewards wallet is updated
    /// @param oldWallet The previous rewards wallet address
    /// @param newWallet The new rewards wallet address
    event RewardsWalletUpdated(address oldWallet, address newWallet);

    /**
     * @notice Initializes the contract with reward parameters
     * @param _rewardsWallet Address of the wallet that holds rewards
     * @param _rewardRatePerDay Initial reward rate per day
     */
    constructor(address _rewardsWallet, uint256 _rewardRatePerDay) {
        if (_rewardRatePerDay > 2000) {
            revert InvalidRewardRate(_rewardRatePerDay);
        }
        if (_rewardsWallet == address(0)) {
            revert InvalidAddress();
        }
        rewardRatePerDay = _rewardRatePerDay;
        rewardsWallet = _rewardsWallet;
        rewardLastUpdateTime = block.timestamp;
    }

    /**
     * @notice Updates the daily reward rate
     * @dev Only callable by the contract owner
     * @param newRewardRate The new reward rate per day
     * @custom:event Emits RewardRateUpdated with old and new values
     */
    function updateRewardRatePerDay(uint256 newRewardRate) external onlyOwner {
        if (newRewardRate > 2000) {
            revert InvalidRewardRate(newRewardRate);
        }

        uint256 oldRewardRate = rewardRatePerDay;
        rewardRatePerDay = newRewardRate;

        uint256 daysElapsed = (block.timestamp - rewardLastUpdateTime) / SECONDS_IN_A_DAY;
        uint256 rewardsAccrued = (rewardRatePerDay * daysElapsed) / 10000;
        rewardAccumulator += rewardsAccrued;

        rewardLastUpdateTime = block.timestamp;

        emit RewardRateUpdated(oldRewardRate, newRewardRate);
    }

    /**
     * @notice Updates the rewards wallet address
     * @dev Only callable by the contract owner
     * @param newWalletAddress The new rewards wallet address
     * @custom:revert InvalidAddress if new wallet address is zero
     * @custom:event Emits RewardsWalletUpdated with old and new values
     */
    function updateRewardsWallet(address newWalletAddress) external onlyOwner {
        if (newWalletAddress == address(0)) {
            revert InvalidAddress();
        }
        emit RewardsWalletUpdated(rewardsWallet, newWalletAddress);
        rewardsWallet = newWalletAddress;
    }
}
