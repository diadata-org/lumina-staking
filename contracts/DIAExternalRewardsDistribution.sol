// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract DIAExternalRewardsDistribution is Ownable {
    IERC20 public immutable REWARDS_TOKEN;

    address public rewardsWallet;

    error InvalidAddress();

    event RewardsWalletUpdated(address oldWallet, address newWallet);

    constructor(
        address rewardsTokenAddress,
        address newRewardsWallet
    ) {
        REWARDS_TOKEN = IERC20(rewardsTokenAddress);
        rewardsWallet = newRewardsWallet;
    }

    function updateRewardsWallet(address newWalletAddress) external onlyOwner {
        if (newWalletAddress == address(0)) {
            revert InvalidAddress();
        }
        emit RewardsWalletUpdated(rewardsWallet, newWalletAddress);

        rewardsWallet = newWalletAddress;
    }
}