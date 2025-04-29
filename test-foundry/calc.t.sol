// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../contracts/DIAWhitelistedStaking.sol";
import "../contracts/DIAExternalStaking.sol";
import "../contracts/DIAStakingCommons.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract StakingComparisonTest is Test {
    MockToken public token;
    DIAWhitelistedStaking public whitelistStaking;
    DIAExternalStaking public externalStaking;
    address public rewardsWallet = address(0xA);
    address public user = address(0xB);
    uint256 public rewardRatePerDay = 10; // 0.001%
    uint256 public amount = 100 * 10 * 10e18;

    

    function testPrintRewardTable() public {
        // console.log("Day | Whitelist Reward | External Reward");
        // for (uint256 i = 1; i <= 30; i++) {
        //     vm.warp(block.timestamp + 1 days);

        //     uint256 wlReward = whitelistStaking.getRewardForStakingStore(0);
        //     uint256 exReward = externalStaking.getRewardForStakingStore(0);

        //     console.log(
        //         string.concat(
        //             vm.toString(i),
        //             " | ",
        //             vm.toString(wlReward),
        //             " | ",
        //             vm.toString(exReward)
        //         )
        //     );
        // }
    }
 

    function pad(
        string memory str,
        uint256 width
    ) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        if (bStr.length >= width) return str;

        bytes memory padded = new bytes(width);
        uint256 padLength = width - bStr.length;

        for (uint256 i = 0; i < padLength; i++) {
            padded[i] = 0x20; // space
        }

        for (uint256 i = 0; i < bStr.length; i++) {
            padded[padLength + i] = bStr[i];
        }

        return string(padded);
    }

    function printRow(
        uint256 day,
        uint256 wlReward,
        uint256 exReward
    ) internal {
        console.log(
            string.concat(
                pad(vm.toString(day), 2),
                " | ",
                pad(vm.toString(wlReward / 1e18), 10),
                " | ",
                pad(vm.toString(exReward / 1e18), 10)
            )
        );
    }

    function test_DailyUnstakeComparison() public {
        console.log("Days | WL Reward | EX Reward");

        for (uint256 daysStaked = 1; daysStaked <= 15; daysStaked++) {
            simulateSingleContractCycle(daysStaked);
        }
    }

    function simulateSingleContractCycle(uint256 daysStaked) internal {
        uint256 principal = 1000e18;
        uint256 rewardRatePerDay = 10 * 1e8;

        // Deploy new token and mint balances
        MockToken stakingToken = new MockToken("Mock", "MCK", 18);
        stakingToken.mint(user, principal * 2);
        stakingToken.mint(rewardsWallet, principal * 100);

        vm.startPrank(user);

        // Deploy fresh staking contracts
        DIAWhitelistedStaking wl = new DIAWhitelistedStaking(
            1 days,
            address(stakingToken),
            rewardsWallet,
            rewardRatePerDay
        );

        DIAExternalStaking ex = new DIAExternalStaking(
            1 days,
            address(stakingToken),
            rewardsWallet,
            rewardRatePerDay,
            1_000_000e18
        );

        // Approvals and setup
        wl.addWhitelistedStaker(user);
        stakingToken.approve(address(wl), type(uint256).max);
        stakingToken.approve(address(ex), type(uint256).max);
        ex.setWithdrawalCapBps(10000);
        wl.setWithdrawalCapBps(10000);

        // Stake
        wl.stake(principal);
        ex.stake(principal, 0);
        vm.stopPrank();

        vm.startPrank(rewardsWallet);
        stakingToken.approve(address(wl), type(uint256).max);

        stakingToken.approve(address(ex), type(uint256).max);
        vm.stopPrank();

        // Wait for `daysStaked` days
        skip(daysStaked * 1 days);

        // Request unstake
        vm.prank(user);
        wl.requestUnstake(1);
        vm.prank(user);
        ex.requestUnstake(1);

        skip(1 days); // unstaking delay

        // Unstake and check rewards
        uint256 wlBefore = stakingToken.balanceOf(user);
        uint256 exBefore = stakingToken.balanceOf(user);

        (, , , uint256 wlPrincipal, , , , ,,, ) = wl.stakingStores(1);
        (, , , uint256 exPrincipal, , , , ,,, ) = ex.stakingStores(2);

        vm.prank(user);
        wl.unstake(1);
        vm.prank(user);
        ex.unstake(1, exPrincipal);

        uint256 wlAfter = stakingToken.balanceOf(user);
        uint256 exAfter = stakingToken.balanceOf(user);

        


        uint256 wlReceived = wlAfter > wlBefore ? wlAfter - wlBefore : 0;
        uint256 exReceived = exAfter > exBefore ? exAfter - exBefore : 0;


        // console.log("exAfter",exAfter);
        // console.log("wlAfter",exAfter);

        // console.log("wlReceived",wlReceived);
        // console.log("exReceived",exReceived);

        //         console.log("principal",principal);



 

        

        printRow(daysStaked, wlReceived, exReceived);
    }
}
