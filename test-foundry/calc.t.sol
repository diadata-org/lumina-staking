// // SPDX-License-Identifier: UNLICENSED
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

    address public userWl = address(0xab);
    address public userEx = address(0xac);
    address public userWl2 = address(0xae);
    address public userEx2 = address(0xad);

    uint256 public rewardRatePerDay = 10; // 0.001%
    uint256 public amount = 100 * 10 * 10e18;

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
                pad(vm.toString(wlReward), 10),
                " | ",
                pad(vm.toString(exReward), 10)
            )
        );
    }

  function printEth(string memory label, uint256 weiAmount) internal view {
    uint256 ethWhole = weiAmount / 1e18;
    uint256 ethDecimals = (weiAmount % 1e18) ; // 4 decimal digits

    // Make sure you convert both to strings
    console.log("%s: %s.%s DIA", label, vm.toString(ethWhole), vm.toString(ethDecimals));
}

    function test_DailyUnstakeComparison() public {
        console.log("Days | WL Reward | EX Reward");

        for (uint256 daysStaked = 1; daysStaked <= 15; daysStaked++) {
            simulateSingleContractCycle(daysStaked);
        }
    }

    function simulateSingleContractCycle(uint256 daysStaked) internal {
        uint256 principal = 10000 * 10e18;
        uint256 rewardRatePerDay = 12 * 1e18;

        // Deploy new token and mint balances
        MockToken stakingToken = new MockToken("Mock", "MCK", 18);
        stakingToken.mint(userWl, principal * 2);
        stakingToken.mint(userEx, principal * 2);

        stakingToken.mint(rewardsWallet, principal * 100);

        DIAWhitelistedStaking wl = new DIAWhitelistedStaking(
            1 days,
            address(stakingToken),
            rewardsWallet,
            rewardRatePerDay
        );

        DIAExternalStaking ex = new DIAExternalStaking(
            1 days,
            address(stakingToken),
            1_000_000e18
        );

        wl.addWhitelistedStaker(userWl);
        ex.setWithdrawalCapBps(10000);
        wl.setWithdrawalCapBps(10000);

        vm.prank(rewardsWallet);
        stakingToken.approve(address(ex), type(uint256).max);
   

        // userwl stake to wl
        vm.startPrank(userWl);

        // Approvals and setup
        stakingToken.approve(address(wl), type(uint256).max);

        // Stake
        wl.stake(principal);

        vm.stopPrank();

        vm.startPrank(userEx);
        stakingToken.approve(address(ex), type(uint256).max);

        ex.stake(principal, 0);
        vm.stopPrank();

        vm.startPrank(rewardsWallet);
        stakingToken.approve(address(wl), type(uint256).max);
        stakingToken.approve(address(ex), type(uint256).max);
        vm.stopPrank();

        // Wait for `daysStaked` days
        skip(daysStaked * 1 days);

        // Request unstake
        vm.prank(userWl);
        wl.requestUnstake(1);
        vm.prank(userEx);
        ex.requestUnstake(1);

             vm.prank(rewardsWallet);

        ex.addRewardToPool(rewardRatePerDay);

        skip(1 days); // unstaking delay

        // Unstake and check rewards
        uint256 wlBefore = stakingToken.balanceOf(userWl);
        uint256 exBefore = stakingToken.balanceOf(userEx);

        (, , , uint256 wlPrincipal, , , , ,  ) = wl.stakingStores(1);

        (, , , uint256 exPrincipal, , , , ) = ex.stakingStores(1);

        vm.prank(userWl);
        wl.unstake(1);
                        uint256 rewards = ex.getRewardForStakingStore(1);

        vm.prank(userEx);

        ex.unstake(1, exPrincipal + rewards);

        uint256 wlAfter = stakingToken.balanceOf(userWl);
        uint256 exAfter = stakingToken.balanceOf(userEx);

        // console.log("exBefore",exBefore);
        // console.log("exAfter",exAfter);

        // console.log("wlBefore",wlBefore);
        //         console.log("wlAfter",wlAfter);

        uint256 wlReceived = wlAfter > wlBefore ? wlAfter - wlBefore : 0;

        uint256 exReceived = exAfter > exBefore ? exAfter - exBefore : 0;

        // console.log("exPrincipal",exPrincipal);
        // console.log("exReceived",exReceived);

        // console.log("wlPrincipal",wlPrincipal);

        printRow(daysStaked, wlReceived, exReceived-exPrincipal );
    }

    function test_DailyRewardDistribution() public {
        // Different principal amounts for each user
        uint256 principal1 = 10000 * 10e18;  // 100,000 tokens
        uint256 principal2 = 5000 * 10e18;   // 50,000 tokens
        uint256 dailyReward = 12 * 1e18;
        uint256 rewardRatePerDay = 12;

        uint256 daysToSimulate = 15;

        // Deploy new token and mint balances
        MockToken stakingToken = new MockToken("Mock", "MCK", 18);
        stakingToken.mint(userWl, principal1 * 2);
        stakingToken.mint(userWl2, principal2 * 2);
        stakingToken.mint(userEx, principal1 * 2);
        stakingToken.mint(userEx2, principal2 * 2);
        stakingToken.mint(rewardsWallet, principal1 * 100);

        DIAWhitelistedStaking wl = new DIAWhitelistedStaking(
            1 days,
            address(stakingToken),
            rewardsWallet,
            rewardRatePerDay
        );

        DIAExternalStaking ex = new DIAExternalStaking(
            1 days,
            address(stakingToken),
            1_000_000e18
        );

        // Add both whitelist users
        wl.addWhitelistedStaker(userWl);
        wl.addWhitelistedStaker(userWl2);
        
        ex.setWithdrawalCapBps(10000);
        wl.setWithdrawalCapBps(10000);

        // Approve rewards wallet for both contracts
        vm.startPrank(rewardsWallet);
        stakingToken.approve(address(ex), type(uint256).max);
        stakingToken.approve(address(wl), type(uint256).max);
        vm.stopPrank();

        // Initial stakes for whitelist users
        vm.startPrank(userWl);
        stakingToken.approve(address(wl), type(uint256).max);
        wl.stake(principal1);
        vm.stopPrank();

        // Second whitelist user stakes
        vm.startPrank(userWl2);
        stakingToken.approve(address(wl), type(uint256).max);
        wl.stake(principal2);
        vm.stopPrank();

        // First user stakes in external staking
        vm.startPrank(userEx);
        stakingToken.approve(address(ex), type(uint256).max);
        ex.stake(principal1, 0);
        vm.stopPrank();

        // Second user stakes in external staking
        vm.startPrank(userEx2);
        stakingToken.approve(address(ex), type(uint256).max);
        ex.stake(principal2, 0);
        vm.stopPrank();

        console.log("\nInitial Stake Amounts:");
        console.log("Whitelist User 1 Principal: %s", vm.toString(principal1 / 1e18));
        console.log("Whitelist User 2 Principal: %s", vm.toString(principal2 / 1e18));
        console.log("External User 1 Principal: %s", vm.toString(principal1 / 1e18));
        console.log("External User 2 Principal: %s", vm.toString(principal2 / 1e18));

        // Simulate daily rewards for specified number of days
        for (uint256 day = 1; day <= daysToSimulate; day++) {
            // Add daily rewards
            vm.startPrank(rewardsWallet);
            ex.addRewardToPool(dailyReward);
            vm.stopPrank();

            // Skip to next day
            skip(1 days);

            // Log daily state
            console.log("\nDay %d:", day);
            printEth("Whitelist User 1", wl.getRewardForStakingStore(1));
            printEth("Whitelist User 2", wl.getRewardForStakingStore(2));
            printEth("External User 1", ex.getRewardForStakingStore(1));
            printEth("External User 2", ex.getRewardForStakingStore(2));
            console.log("---");
        }

        // Request unstake after simulation period
        vm.prank(userWl);
        wl.requestUnstake(1);
        vm.prank(userWl2);
        wl.requestUnstake(2);
        vm.prank(userEx);
        ex.requestUnstake(1);
        vm.prank(userEx2);
        ex.requestUnstake(2);

        skip(1 days); // unstaking delay

        // Unstake and check final rewards
        uint256 wlBefore = stakingToken.balanceOf(userWl);
        uint256 wl2Before = stakingToken.balanceOf(userWl2);
        uint256 exBefore = stakingToken.balanceOf(userEx);
        uint256 ex2Before = stakingToken.balanceOf(userEx2);

        // First whitelist user unstake
        vm.startPrank(userWl);
        wl.unstake(1);
        vm.stopPrank();

        // Second whitelist user unstake
        vm.startPrank(userWl2);
        wl.unstake(2);
        vm.stopPrank();

        // First external user unstake
        vm.startPrank(userEx);
        ex.unstake(1, principal1 + ex.getRewardForStakingStore(1));
        vm.stopPrank();

        // Second external user unstake
        vm.startPrank(userEx2);
        ex.unstake(2, principal2 + ex.getRewardForStakingStore(2));
        vm.stopPrank();

        console.log("\nFinal Results:");
        console.log("Whitelist User 1:");
        console.log("  Principal: %.2f tokens", principal1 / 1e18);
        console.log("  Total Rewards: %.2f tokens", (stakingToken.balanceOf(userWl) - wlBefore) / 1e18);
        console.log("  Reward Percentage: %.2f%%", ((stakingToken.balanceOf(userWl) - wlBefore) * 100) / principal1);
        
        console.log("\nWhitelist User 2:");
        console.log("  Principal: %.2f tokens", principal2 / 1e18);
        console.log("  Total Rewards: %.2f tokens", (stakingToken.balanceOf(userWl2) - wl2Before) / 1e18);
        console.log("  Reward Percentage: %.2f%%", ((stakingToken.balanceOf(userWl2) - wl2Before) * 100) / principal2);
        
        console.log("\nExternal User 1:");
        console.log("  Principal: %.2f tokens", principal1 / 1e18);
        console.log("  Total Rewards: %.2f tokens", (stakingToken.balanceOf(userEx) - exBefore) / 1e18);
        console.log("  Reward Percentage: %.2f%%", ((stakingToken.balanceOf(userEx) - exBefore) * 100) / principal1);
        
        console.log("\nExternal User 2:");
        console.log("  Principal: %.2f tokens", principal2 / 1e18);
        console.log("  Total Rewards: %.2f tokens", (stakingToken.balanceOf(userEx2) - ex2Before) / 1e18);
        console.log("  Reward Percentage: %.2f%%", ((stakingToken.balanceOf(userEx2) - ex2Before) * 100) / principal2);
    }
}
