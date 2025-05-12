// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract DIAExternalRewardsDistribution is Ownable {
    IERC20 public immutable REWARDS_TOKEN;

    error InvalidAddress();

    constructor(address rewardsTokenAddress) {
        REWARDS_TOKEN = IERC20(rewardsTokenAddress);
    }
}
