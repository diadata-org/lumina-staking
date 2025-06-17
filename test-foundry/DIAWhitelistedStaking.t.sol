// SPDX-License-Identifier: GPL
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DIAWhitelistedStaking} from "../contracts/DIAWhitelistedStaking.sol";
import {WDIA} from "../contracts/WDIA.sol";
import "../contracts/StakingErrorsAndEvents.sol";


contract DIAWhitelistedStakingTest is Test {
    DIAWhitelistedStaking public staking;
    WDIA public wdia;
    address public rewardsWallet;
    address public staker;
    address public beneficiary;
    address public owner;
    uint256 public constant STAKING_AMOUNT = 1 * 1e18;
    uint256 public constant REWARD_RATE_PER_DAY = 2000; // 20% per day (2000 basis points)
    uint256 public constant UNSTAKING_DURATION = 7 days;
    uint256 public constant SECONDS_IN_A_DAY = 86400;

    event StakerAddressAdded(address newStaker);
    event Staked(address indexed staker, address indexed beneficiary, uint256 amount, uint256 stakingStoreIndex);
    event Claimed(uint256 indexed stakingStoreIndex, uint256 principalAmount, uint256 principalWalletReward, uint256 beneficiaryReward, address principalPayoutWallet, address beneficiary);

    function padDecimal(uint256 value, uint256 decimals) internal pure returns (string memory) {
        string memory decimalStr = vm.toString(value);
        if (bytes(decimalStr).length >= decimals) {
            return decimalStr;
        }
        
        string memory padding = "";
        for (uint256 i = bytes(decimalStr).length; i < decimals; i++) {
            padding = string.concat(padding, "0");
        }
        return string.concat(padding, decimalStr);
    }

    function formatAmount(uint256 amount) internal pure returns (string memory) {
        return string.concat(
            vm.toString(amount / 1e18),
            ".",
            padDecimal((amount % 1e18) / 1e14, 4)
        );
    }

    function setUp() public {
        // Deploy WDIA token
        wdia = new WDIA();

        // vm.warp(block.timestamp + 1 days);

        // Setup accounts
        owner = makeAddr("owner");
        rewardsWallet = makeAddr("rewardsWallet");
        staker = makeAddr("staker");
        beneficiary = makeAddr("beneficiary");
        
        // Fund accounts
        vm.deal(owner, 10000 * 1e18);
        vm.deal(rewardsWallet, 100000000 * 10e18);
        vm.deal(staker, 10000 * 1e18);
        
        // Deploy staking contract as owner
        vm.startPrank(owner);
        staking = new DIAWhitelistedStaking(
            UNSTAKING_DURATION,
            address(wdia),
            rewardsWallet,
            REWARD_RATE_PER_DAY
        );

        // Add staker and beneficiary to whitelist
        staking.addWhitelistedStaker(staker);
        staking.addWhitelistedStaker(beneficiary);
        vm.stopPrank();

        // Fund rewards wallet with WDIA tokens
        vm.startPrank(rewardsWallet);
        wdia.deposit{value: 100000000 * 10e18}();
        wdia.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        // Fund staker with WDIA tokens
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }

    

    function test_StakeAndCalculateRewards() public {
        // Stake tokens
        vm.startPrank(staker);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 900); // 90% to principal wallet
        vm.stopPrank();

        // Get staking store index
        uint256 stakingStoreIndex = 1;

        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);

        // Claim rewards
        vm.prank(beneficiary);
        staking.claim(stakingStoreIndex);

        // Check balances
        uint256 expectedTotalReward = (STAKING_AMOUNT * REWARD_RATE_PER_DAY) / 10000; // 20% of staked amount
        uint256 expectedPrincipalShare = (expectedTotalReward * 900) / 10000; // 90% of reward
        uint256 expectedBeneficiaryShare = expectedTotalReward - expectedPrincipalShare; // 10% of reward

        assertEq(wdia.balanceOf(beneficiary), expectedBeneficiaryShare, "Beneficiary should receive 10% of rewards");
        assertEq(wdia.balanceOf(staker), expectedPrincipalShare, "Principal wallet should receive 90% of rewards");
    }

    function test_UnstakingWithRewards() public {
        // Stake tokens
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 100); // 90% to principal wallet
        vm.stopPrank();

        uint256 stakingStoreIndex = 1;

        // Advance time by 7 days
        vm.warp(block.timestamp + 7 days);

        // Get initial balances
        uint256 initialStakerBalance = wdia.balanceOf(staker);
        uint256 initialBeneficiaryBalance = wdia.balanceOf(beneficiary);

        // Claim rewards
        vm.prank(beneficiary);
        staking.claim(stakingStoreIndex);

        // Get balances after claiming rewards
        uint256 afterClaimStakerBalance = wdia.balanceOf(staker);
        uint256 afterClaimBeneficiaryBalance = wdia.balanceOf(beneficiary);

        // Calculate reward amounts
        uint256 stakerReward = afterClaimStakerBalance - initialStakerBalance;
        uint256 beneficiaryReward = afterClaimBeneficiaryBalance - initialBeneficiaryBalance;

        // Request unstake
        vm.prank(beneficiary);
        staking.requestUnstake(stakingStoreIndex);

        console2.log("unstakingRequestTime", UNSTAKING_DURATION);
        console2.log("block.timestamp", block.timestamp);

        // Advance time by unstaking duration
        vm.warp(block.timestamp + 7 days + 7 days);

        // Get balance before unstaking
        uint256 balanceBeforeUnstake = wdia.balanceOf(staker);

        // Unstake
        vm.prank(staker);
        staking.unstake(stakingStoreIndex);

        // Get final balance
        uint256 finalBalance = wdia.balanceOf(staker);
        uint256 unstakeAmount = finalBalance - balanceBeforeUnstake;

  
 
        assertEq(unstakeAmount, STAKING_AMOUNT, "Staker should receive exactly the staked amount back");
        assertEq(finalBalance, initialStakerBalance + stakerReward + STAKING_AMOUNT, "Final balance should be initial + rewards + principal");
    }

    function test_RewardsAccumulator() public {
        // Create first stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        // Advance time by 7 days to accumulate rewards
        vm.warp(block.timestamp + 7 days);

        // Get initial balances for staker 1
        uint256 initialStaker1Balance = wdia.balanceOf(staker);

        // Staker 1 claims rewards on day 7
        vm.prank(staker);
        staking.claim(1);

        // Get final balances for staker 1
        uint256 finalStaker1Balance = wdia.balanceOf(staker);
        uint256 totalRewardsStaker1 = (finalStaker1Balance - initialStaker1Balance);

        // Expected rewards for 7 days: 1.4 tokens (20% per day * 7 days = 140%)
        uint256 expectedRewardsStaker1 = (STAKING_AMOUNT * 14000) / 10000; // Using basis points (2000 = 20%)

        assertEq(totalRewardsStaker1, expectedRewardsStaker1, "Staker 1 should receive 1.4 tokens after 7 days");

        // Create a new staker and beneficiary
        address newStaker = makeAddr("newStaker");
        address newBeneficiary = makeAddr("newBeneficiary");
        vm.deal(newStaker, STAKING_AMOUNT);

        // Get initial balances for staker 2
        uint256 initialStaker2Balance = wdia.balanceOf(newStaker);

        // Add new staker to whitelist
        vm.startPrank(owner);
        staking.addWhitelistedStaker(newStaker);
        staking.addWhitelistedStaker(newBeneficiary);
        vm.stopPrank();

        // Create second stake on day 7
        vm.startPrank(newStaker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(newBeneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        // Advance time by 2 more days (to day 9)
        vm.warp(block.timestamp + 2 days);

        // Staker 2 claims rewards on day 9
        vm.prank(newStaker);
        staking.claim(2);

        // Get final balances for staker 2
        uint256 finalStaker2Balance = wdia.balanceOf(newStaker);
        uint256 totalRewardsStaker2 = (finalStaker2Balance - initialStaker2Balance);

        // Expected rewards for 9 days: 0.4 tokens (20% per day * 2 days = 40%)
        uint256 expectedRewardsStaker2 = (STAKING_AMOUNT * 4000) / 10000; // Using basis points (2000 = 20%)
        assertEq(totalRewardsStaker2, expectedRewardsStaker2, "Staker 2 should receive 0.4 tokens after 9 days");

        // Advance time by 3 more days (to day 12)
        vm.warp(block.timestamp + 3 days);

        uint256 initialStaker2BalanceDay12 = wdia.balanceOf(newStaker);

        // Staker 2 claims rewards on day 12
        vm.prank(newStaker);
        staking.claim(2);

        // Get final balances for staker 2
        
        uint256 finalStaker2BalanceDay12 = wdia.balanceOf(newStaker);
        uint256 totalRewardsStaker2Day12 = (finalStaker2BalanceDay12 - initialStaker2BalanceDay12);
        console2.log("initialStaker2BalanceDay12", initialStaker2BalanceDay12);
        console2.log("finalStaker2BalanceDay12", finalStaker2BalanceDay12);
        console2.log("totalRewardsStaker2Day12", totalRewardsStaker2Day12);

        // Expected rewards for 12 days: 0.6 tokens (20% per day * 3 days = 60%)
        uint256 expectedRewardsStaker2Day12 = (STAKING_AMOUNT * 6000) / 10000; // Using basis points (2000 = 20%)
        assertEq(totalRewardsStaker2Day12, expectedRewardsStaker2Day12, "Staker 2 should receive 0.6 tokens after 12 days");

        // Advance time by 2 more days (to day 13)
        vm.warp(block.timestamp + 1 days);
        uint256 cTotalRewardsStaker2 = staking.getTotalRewards(2);
        uint256 cTotalRemainingRewards = staking.getRemainingRewards(2);

        // Log the results
        console2.log("\nStaker 1 Results | Day 7:");
        console2.log("Initial Balance:", formatAmount(initialStaker1Balance));
        console2.log("Final Balance:", formatAmount(finalStaker1Balance));
        console2.log("Total Rewards Received:", formatAmount(totalRewardsStaker1));
        console2.log("Expected Rewards:", formatAmount(expectedRewardsStaker1));

        console2.log("\nStaker 2 Results | Day 9:");
        console2.log("Initial Balance:", formatAmount(initialStaker2Balance));
        console2.log("Final Balance:", formatAmount(finalStaker2Balance));
        console2.log("Total Rewards Received:", formatAmount(totalRewardsStaker2));
        console2.log("Expected Rewards:", formatAmount(expectedRewardsStaker2));

        console2.log("\nStaker 2 Results | Day 12:");
        console2.log("Initial Balance:", formatAmount(initialStaker2BalanceDay12));
        console2.log("Final Balance:", formatAmount(finalStaker2BalanceDay12));
        console2.log("Total Rewards Received:", formatAmount(totalRewardsStaker2Day12));
        console2.log("Expected Rewards:", formatAmount(expectedRewardsStaker2Day12));

        console2.log("\nStaker 2 Results | Day 13:");
        console2.log("Total Rewards Accrued:", cTotalRewardsStaker2);
        console2.log("Remaining Rewards:", cTotalRemainingRewards);
    }

    function test_RemainingRewards() public {
        // Create first stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        
    }

    function test_RewardsOverTime() public {
        // Setup second user
        address staker2 = makeAddr("staker2");
        address beneficiary2 = makeAddr("beneficiary2");
        vm.deal(staker2, 10000 * 1e18);

        // Print header
        console2.log("\nRewards Table");
        console2.log("Initial Stake: 1 WDIA per user");
        console2.log("Daily Reward Rate: 20% (2000 basis points)");
        console2.log("Day | User | Principal WDIA | Total WDIA Rewards | Staker  | Beneficiary  | Total DIA Value");
        console2.log("----|------|---------------|-------------------|---------|--------------|----------------");

        // Test days 1-5
        for (uint256 dayCount = 1; dayCount <= 5; dayCount++) {
            // Reset contract state
            vm.startPrank(owner);
            staking = new DIAWhitelistedStaking(
                UNSTAKING_DURATION,
                address(wdia),
                rewardsWallet,
                REWARD_RATE_PER_DAY
            );
            staking.addWhitelistedStaker(staker);
            staking.addWhitelistedStaker(beneficiary);
            staking.addWhitelistedStaker(staker2);
            staking.addWhitelistedStaker(beneficiary2);
            vm.stopPrank();

            // Reset WDIA balances
            vm.startPrank(rewardsWallet);
            uint256 rewardsBalance = wdia.balanceOf(rewardsWallet);
            if (rewardsBalance > 0) {
                wdia.withdraw(rewardsBalance);
            }
            vm.deal(rewardsWallet, 100000000 * 1e18);
            wdia.deposit{value: 100000000 * 1e18}();
            wdia.approve(address(staking), type(uint256).max);
            vm.stopPrank();

            // Reset and stake for User 1
            vm.startPrank(staker);
            uint256 stakerBalance = wdia.balanceOf(staker);
            if (stakerBalance > 0) {
                wdia.withdraw(stakerBalance);
            }
            vm.deal(staker, STAKING_AMOUNT);
            wdia.deposit{value: STAKING_AMOUNT}();
            wdia.approve(address(staking), type(uint256).max);
            staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
            vm.stopPrank();

            // Reset and stake for User 2
            vm.startPrank(staker2);
            uint256 staker2Balance = wdia.balanceOf(staker2);
            if (staker2Balance > 0) {
                wdia.withdraw(staker2Balance);
            }
            vm.deal(staker2, STAKING_AMOUNT);
            wdia.deposit{value: STAKING_AMOUNT}();
            wdia.approve(address(staking), type(uint256).max);
            staking.stakeForAddress(beneficiary2, STAKING_AMOUNT, 10000); // 100% to principal wallet
            vm.stopPrank();

            // Reset beneficiary balances
            vm.startPrank(beneficiary);
            uint256 beneficiaryBalance = wdia.balanceOf(beneficiary);
            if (beneficiaryBalance > 0) {
                wdia.withdraw(beneficiaryBalance);
            }
            vm.stopPrank();

            vm.startPrank(beneficiary2);
            uint256 beneficiary2Balance = wdia.balanceOf(beneficiary2);
            if (beneficiary2Balance > 0) {
                wdia.withdraw(beneficiary2Balance);
            }
            vm.stopPrank();

            // Advance time
            vm.warp(block.timestamp + dayCount * 1 days);

            // Claim rewards for User 1
            vm.prank(beneficiary);
            staking.claim(1);

            // Get balances for User 1
            uint256 user1Principal = wdia.balanceOf(staker);
            uint256 user1Beneficiary = wdia.balanceOf(beneficiary);
            uint256 user1Total = user1Principal + user1Beneficiary;

            // Print User 1 row
            console2.log(
                string.concat(
                    vm.toString(dayCount),
                    " | User1 | ",
                    formatAmount(STAKING_AMOUNT),
                    " WDIA | ",
                    formatAmount(user1Total),
                    " WDIA | ",
                    formatAmount(user1Principal),
                    " WDIA | ",
                    formatAmount(user1Beneficiary),
                    " WDIA | ",
                    formatAmount(user1Total),
                    " DIA"
                )
            );

            // Claim rewards for User 2
            vm.prank(beneficiary2);
            staking.claim(2);

            // Get balances for User 2
            uint256 user2Principal = wdia.balanceOf(staker2);
            uint256 user2Beneficiary = wdia.balanceOf(beneficiary2);
            uint256 user2Total = user2Principal + user2Beneficiary;

            // Print User 2 row
            console2.log(
                string.concat(
                    vm.toString(dayCount),
                    " | User2 | ",
                    formatAmount(STAKING_AMOUNT),
                    " WDIA | ",
                    formatAmount(user2Total),
                    " WDIA | ",
                    formatAmount(user2Principal),
                    " WDIA | ",
                    formatAmount(user2Beneficiary),
                    " WDIA | ",
                    formatAmount(user2Total),
                    " DIA"
                )
            );
        }

        // Test days 10-100 (every 10 days)
        for (uint256 dayCount = 10; dayCount <= 100; dayCount += 10) {
            // Reset contract state
            vm.startPrank(owner);
            staking = new DIAWhitelistedStaking(
                UNSTAKING_DURATION,
                address(wdia),
                rewardsWallet,
                REWARD_RATE_PER_DAY
            );
            staking.addWhitelistedStaker(staker);
            staking.addWhitelistedStaker(beneficiary);
            staking.addWhitelistedStaker(staker2);
            staking.addWhitelistedStaker(beneficiary2);
            vm.stopPrank();

            // Reset WDIA balances
            vm.startPrank(rewardsWallet);
            uint256 rewardsBalance = wdia.balanceOf(rewardsWallet);
            if (rewardsBalance > 0) {
                wdia.withdraw(rewardsBalance);
            }
            vm.deal(rewardsWallet, 100000000 * 1e18);
            wdia.deposit{value: 100000000 * 1e18}();
            wdia.approve(address(staking), type(uint256).max);
            vm.stopPrank();

            // Reset and stake for User 1
            vm.startPrank(staker);
            uint256 stakerBalance = wdia.balanceOf(staker);
            if (stakerBalance > 0) {
                wdia.withdraw(stakerBalance);
            }
            vm.deal(staker, STAKING_AMOUNT);
            wdia.deposit{value: STAKING_AMOUNT}();
            wdia.approve(address(staking), type(uint256).max);
            staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
            vm.stopPrank();

            // Reset and stake for User 2
            vm.startPrank(staker2);
            uint256 staker2Balance = wdia.balanceOf(staker2);
            if (staker2Balance > 0) {
                wdia.withdraw(staker2Balance);
            }
            vm.deal(staker2, STAKING_AMOUNT);
            wdia.deposit{value: STAKING_AMOUNT}();
            wdia.approve(address(staking), type(uint256).max);
            staking.stakeForAddress(beneficiary2, STAKING_AMOUNT, 10000); // 100% to principal wallet
            vm.stopPrank();

            // Reset beneficiary balances
            vm.startPrank(beneficiary);
            uint256 beneficiaryBalance = wdia.balanceOf(beneficiary);
            if (beneficiaryBalance > 0) {
                wdia.withdraw(beneficiaryBalance);
            }
            vm.stopPrank();

            vm.startPrank(beneficiary2);
            uint256 beneficiary2Balance = wdia.balanceOf(beneficiary2);
            if (beneficiary2Balance > 0) {
                wdia.withdraw(beneficiary2Balance);
            }
            vm.stopPrank();

            // Advance time
            vm.warp(block.timestamp + dayCount * 1 days);

            // Claim rewards for User 1
            vm.prank(beneficiary);
            staking.claim(1);

            // Get balances for User 1
            uint256 user1Principal = wdia.balanceOf(staker);
            uint256 user1Beneficiary = wdia.balanceOf(beneficiary);
            uint256 user1Total = user1Principal + user1Beneficiary;

            // Print User 1 row
            console2.log(
                string.concat(
                    vm.toString(dayCount),
                    " | User1 | ",
                    formatAmount(STAKING_AMOUNT),
                    " WDIA | ",
                    formatAmount(user1Total),
                    " WDIA | ",
                    formatAmount(user1Principal),
                    " WDIA | ",
                    formatAmount(user1Beneficiary),
                    " WDIA | ",
                    formatAmount(user1Total),
                    " DIA"
                )
            );

            // Claim rewards for User 2
            vm.prank(beneficiary2);
            staking.claim(2);

            // Get balances for User 2
            uint256 user2Principal = wdia.balanceOf(staker2);
            uint256 user2Beneficiary = wdia.balanceOf(beneficiary2);
            uint256 user2Total = user2Principal + user2Beneficiary;

            // Print User 2 row
            console2.log(
                string.concat(
                    vm.toString(dayCount),
                    " | User2 | ",
                    formatAmount(STAKING_AMOUNT),
                    " WDIA | ",
                    formatAmount(user2Total),
                    " WDIA | ",
                    formatAmount(user2Principal),
                    " WDIA | ",
                    formatAmount(user2Beneficiary),
                    " WDIA | ",
                    formatAmount(user2Total),
                    " DIA"
                )
            );
        }

        // Print summary
        console2.log("\nSummary:");
        console2.log("User 1 :");
        console2.log("- Initial Stake: 1 WDIA");
        console2.log("- Final Principal Balance: ", formatAmount(wdia.balanceOf(staker)), " WDIA");
        console2.log("- Final Beneficiary Balance: ", formatAmount(wdia.balanceOf(beneficiary)), " WDIA");
        console2.log("- Total Rewards: ", formatAmount(wdia.balanceOf(staker) + wdia.balanceOf(beneficiary)), " WDIA");

        console2.log("\nUser 2 :");
        console2.log("- Initial Stake: 1 WDIA");
        console2.log("- Final Principal Balance: ", formatAmount(wdia.balanceOf(staker2)), " WDIA");
        console2.log("- Final Beneficiary Balance: ", formatAmount(wdia.balanceOf(beneficiary2)), " WDIA");
        console2.log("- Total Rewards: ", formatAmount(wdia.balanceOf(staker2) + wdia.balanceOf(beneficiary2)), " WDIA");
    }

    function test_WhitelistManagement() public {
        // Test adding staker to whitelist
        address newStaker = makeAddr("newStaker");
        vm.startPrank(owner);
        staking.addWhitelistedStaker(newStaker);
        assertTrue(staking.stakingWhitelist(newStaker), "Staker should be whitelisted");

        // Test removing staker from whitelist
        staking.removeWhitelistedStaker(newStaker);
        assertFalse(staking.stakingWhitelist(newStaker), "Staker should be removed from whitelist");

        // Test adding already whitelisted staker
        vm.expectRevert(DIAWhitelistedStaking.AlreadyWhitelisted.selector);
        staking.addWhitelistedStaker(staker);

        // Test removing non-whitelisted staker
        vm.expectRevert(NotWhitelisted.selector);
        staking.removeWhitelistedStaker(newStaker);
        vm.stopPrank();
    }

    function test_StakingFunctionality() public {
        // Test direct staking
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stake(STAKING_AMOUNT);
        vm.stopPrank();

        // Verify stake was created
        uint256 stakingStoreIndex = 1;
        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 paidOutReward,
            uint64 stakingStartTime,
            uint64 unstakingRequestTime,
            uint32 principalWalletShareBps,
            uint256 rewardAccumulator,
            uint256 initialRewardAccumulator,
            uint256 pendingRewards,
            bool isClaimable,
            uint64 lastClaimTime
        ) = staking.stakingStores(stakingStoreIndex);
        
        assertEq(principalPayoutWallet, staker, "Principal wallet should be staker");
        assertEq(beneficiary, staker, "Beneficiary should be staker");
        assertEq(principal, STAKING_AMOUNT, "Principal amount should match");
        assertEq(stakingStartTime, block.timestamp, "Staking start time should be current timestamp");

        // Test staking for another address
        address newBeneficiary = makeAddr("newBeneficiary");
        vm.startPrank(owner);
        staking.addWhitelistedStaker(newBeneficiary);
        vm.stopPrank();

        vm.startPrank(staker);
        staking.stakeForAddress(newBeneficiary, STAKING_AMOUNT, 5000); // 50/50 split
        vm.stopPrank();

        // Verify stake for another address
        stakingStoreIndex = 2;
        (
            beneficiary,
            principalPayoutWallet,
            principalUnstaker,
            principal,
            paidOutReward,
            stakingStartTime,
            unstakingRequestTime,
            principalWalletShareBps,
            rewardAccumulator,
            initialRewardAccumulator,
            pendingRewards,
            isClaimable,
            lastClaimTime
        ) = staking.stakingStores(stakingStoreIndex);
        
        assertEq(principalPayoutWallet, staker, "Principal wallet should be staker");
        assertEq(beneficiary, newBeneficiary, "Beneficiary should be new beneficiary");
        assertEq(principal, STAKING_AMOUNT, "Principal amount should match");
    }

    

    function test_UnstakingProcess() public {
        // Setup stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 5000); // 50/50 split
        vm.stopPrank();

        // Test unstaking process
        vm.warp(block.timestamp + 1 days);
        
        // Request unstake
        vm.prank(beneficiary);
        staking.requestUnstake(1);
        
        // Try to unstake before duration
        vm.prank(staker);
        vm.expectRevert(UnstakingPeriodNotElapsed.selector);
        staking.unstake(1);

        // Wait for unstaking duration
        vm.warp(block.timestamp + UNSTAKING_DURATION);

        // Try to unstake with wrong account
        vm.prank(beneficiary);
        vm.expectRevert(NotPrincipalUnstaker.selector);
        staking.unstake(1);

        // Get balance before unstaking
        uint256 balanceBefore = wdia.balanceOf(staker);

        // Complete unstake
        vm.prank(staker);
        staking.unstake(1);

        // Get balance after unstaking
        uint256 balanceAfter = wdia.balanceOf(staker);
        uint256 balanceDifference = balanceAfter - balanceBefore;

        // Verify unstaking
        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 paidOutReward,
            uint64 stakingStartTime,
            uint64 unstakingRequestTime,
            uint32 principalWalletShareBps,
            uint256 rewardAccumulator,
            uint256 initialRewardAccumulator,
            uint256 pendingRewards,
            bool isClaimable,
            uint64 lastClaimTime
        ) = staking.stakingStores(1);
        
        assertEq(unstakingRequestTime, 0, "Unstaking request time should be reset");
        assertEq(balanceDifference, STAKING_AMOUNT, "Staker should receive exactly the staked amount back");
    }

    function test_MaxStakesPerBeneficiary() public {
        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT * 2}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 5000);
        vm.stopPrank();

        // Set max stakes per beneficiary to 1
        vm.startPrank(owner);
        staking.setMaxStakesPerBeneficiary(1);
        vm.stopPrank();

        // Try to create second stake
        vm.startPrank(staker);
        vm.expectRevert();
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 5000);
        vm.stopPrank();

        // Increase max stakes and try again
        vm.startPrank(owner);
        staking.setMaxStakesPerBeneficiary(2);
        vm.stopPrank();

        vm.startPrank(staker);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 5000);
        vm.stopPrank();

        // Verify stake count
        uint256 stakeCount = staking.getStakesCountForBeneficiary(beneficiary);
        assertEq(stakeCount, 2, "Beneficiary should have 2 stakes");
    }

    function test_DailyRewardsLoop() public {
        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        uint256 initial = 86400;

        // // Day 1
        // uint256 day1 = initial + 1 days;
        // vm.warp(day1);
        // uint256 totalRewards = staking.getTotalRewards(1);
        // console2.log("Day 1 totalRewards", totalRewards);

        // // Day 2
        // uint256 day2 = initial + 2 days;
        // vm.warp(day2);
        // totalRewards = staking.getTotalRewards(1);
        // console2.log("Day 2 totalRewards", totalRewards);

        // // Day 3
        // uint256 day3 = initial + 3 days;
        // vm.warp(day3);
        // totalRewards = staking.getTotalRewards(1);
        // console2.log("Day 3 totalRewards", totalRewards);

        // // Day 4
        // uint256 day4 = initial + 4 days;
        // vm.warp(day4);
        // totalRewards = staking.getTotalRewards(1);
        // console2.log("Day 4 totalRewards", totalRewards);          

        // Print header
        console2.log("\nDaily Rewards Tracking");
        console2.log("Day | Total Rewards | Remaining Rewards");
        console2.log("----|---------------|-----------------");

        // Loop through 3 days
        for (uint256 dayCount = 1; dayCount <= 20; dayCount++) {
            // Advance time by 1 day
            uint256 timestamp = initial + (dayCount * 1 days);
            vm.warp(timestamp);

            // Get rewards information
            uint256 totalRewards = staking.getTotalRewards(1);

            // Claim rewards for User 1 on Day 5
            if (dayCount == 5) {
                vm.prank(beneficiary);
                staking.claim(1);
            }

            // Claim rewards for User 1 on Day 5
            if (dayCount == 9) {
                vm.prank(beneficiary);
                staking.claim(1);
            }

            uint256 remainingRewards = staking.getRemainingRewards(1);

            // Print daily information
            console2.log(
                string.concat(
                    vm.toString(dayCount),
                    " |          ",
                    formatAmount(totalRewards),
                    " |        ",
                    formatAmount(remainingRewards)
                )
            );
        }
    }

    function test_SpamClaim() public {
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        // Advance time by 7 days to accumulate rewards => rewards = 1.4 tokens
        vm.warp(block.timestamp + 7 days);

        // Get initial balances for staker 2
        uint256 initialStaker1Balance = wdia.balanceOf(staker);

        // Create a new staker and beneficiary
        address newStaker = makeAddr("newStaker");
        address newBeneficiary = makeAddr("newBeneficiary");
        vm.deal(newStaker, STAKING_AMOUNT);

        // Get initial balances for staker 2
        uint256 initialStaker2Balance = wdia.balanceOf(newStaker);

        // Add new staker to whitelist
        vm.startPrank(owner);
        staking.addWhitelistedStaker(newStaker);
        staking.addWhitelistedStaker(newBeneficiary);
        vm.stopPrank();               

        // Create second stake on day 7
        vm.startPrank(newStaker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(newBeneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        // Attacker repeatedly calls claim() within the same day - start of day 8
        uint256 initialTimestamp = 691201;
        for (uint256 hourCount = 1; hourCount <= 10; hourCount++) {
            vm.warp(initialTimestamp + (hourCount * 1 hours)); // advance by 1 hour
            vm.prank(newBeneficiary);
            staking.claim(2); // attacker stake index is 2
        }

        // After 1 day, Staker A tries to claim - start of day 9
        // Staker 1 rewards = 1.6 tokens
        vm.warp(block.timestamp + (1 days - 10 hours)); // complete the day
        vm.prank(staker);
        staking.claim(1);

        uint256 staker1Rewards = staking.getTotalRewards(1);
        // OR
        uint256 finalStaker1Balance = wdia.balanceOf(staker);
        uint256 totalStaker1Rewards = finalStaker1Balance - initialStaker1Balance;
        
        uint256 expectedReward = (STAKING_AMOUNT * 16000) / 10000;

        assertEq(staker1Rewards, expectedReward, "Staker 1 rewards should be 1.6 tokens");

        console2.log("\nSummary:");
        console2.log("Staker 1 :");
        console2.log("- Total Rewards | getTotalRewards:", formatAmount(staker1Rewards));
        console2.log("- Total Rewards | balanceOf:", formatAmount(totalStaker1Rewards));
        console2.log("- Expected Rewards: ", formatAmount(expectedReward));
    }

    function test_RewardRateUpdate() public {
        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        
        // Initial reward rate is 20% per day (2000 basis points)
        uint256 initialRewardRate = staking.rewardRatePerDay();
        assertEq(initialRewardRate, 2000, "Initial reward rate should be 2000 basis points (20%)");

        // Advance time by 5 days
        uint256 day5 = 432001;
        vm.warp(day5);

        // Get rewards before rate update
        uint256 rewardsBeforeUpdate = staking.getTotalRewards(1);
        uint256 expectedRewardsBeforeUpdate = (STAKING_AMOUNT * initialRewardRate * 5) / 10000;
        assertEq(rewardsBeforeUpdate, expectedRewardsBeforeUpdate, "Rewards before update should be 1 tokens");

        // Update reward rate to 15% per day (1500 basis points)
        vm.startPrank(owner);
        staking.updateRewardRatePerDay(1500);
        vm.stopPrank();

        // Verify new rate
        uint256 newRewardRate = staking.rewardRatePerDay();
        assertEq(newRewardRate, 1500, "New reward rate should be 1500 basis points (15%)");

        // Advance time by 1 more day
        uint256 day6 = day5 + SECONDS_IN_A_DAY;
        vm.warp(day6);

        // Get total rewards after rate update
        uint256 totalRewards = staking.getTotalRewards(1);
        
        // Calculate expected rewards:
        // First 5 days: 20% per day = 100%
        // Next 5 days: 15% per day = 75%
        // Total: 175% --> 1.75 tokens
        uint256 expectedTotalRewards = expectedRewardsBeforeUpdate + (STAKING_AMOUNT * 1500) / 10000; // 0.15 increase
        
        console2.log("\nReward Rate Update Test Results:");
        console2.log("Initial Reward Rate:", initialRewardRate);
        console2.log("New Reward Rate:", newRewardRate);
        console2.log("Rewards Before Update:", formatAmount(rewardsBeforeUpdate));
        console2.log("Total Rewards After Update:", formatAmount(totalRewards));
        console2.log("Expected Total Rewards:", formatAmount(expectedTotalRewards));

        assertEq(totalRewards, expectedTotalRewards, "Total rewards should be 175% (100% from first 5 days + 75% from next 5 days)");

        // // Claim rewards and verify actual token transfers
        // uint256 initialBalance = wdia.balanceOf(staker);
        // vm.prank(beneficiary);
        // staking.claim(1);
        // uint256 finalBalance = wdia.balanceOf(staker);
        // uint256 actualRewards = finalBalance - initialBalance;

        // console2.log("\nActual Rewards Received:");
        // console2.log("Initial Balance:", formatAmount(initialBalance));
        // console2.log("Final Balance:", formatAmount(finalBalance));
        // console2.log("Actual Rewards:", formatAmount(actualRewards));

        // assertEq(actualRewards, expectedTotalRewards, "Actual rewards received should match expected total rewards");
    }

    function test_stakeCreation() public {
        // Staker 1 stakes on start ofDay 2
        uint256 day2 = 172801;
        vm.warp(day2);
        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        // Create a new staker and beneficiary
        address staker2 = makeAddr("staker2");
        address newBeneficiary = makeAddr("newBeneficiary");
        vm.deal(staker2, STAKING_AMOUNT);

        // Add new staker to whitelist
        vm.startPrank(owner);
        staking.addWhitelistedStaker(staker2);
        staking.addWhitelistedStaker(newBeneficiary);
        vm.stopPrank();     


        // Staker 2 stakes on start of Day 3
        uint256 day3 = day2 + 86400;
        vm.warp(day3);
        // Create second stake on day 2
        vm.startPrank(staker2);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stake(STAKING_AMOUNT); // 100% to principal wallet
        vm.stopPrank();

        uint256 initialStaker1Balance = wdia.balanceOf(staker);
        uint256 initialStaker2Balance = wdia.balanceOf(staker2);

        // Stakers claim on start of Day 4
        uint256 day4 = day3 + 86400;
        vm.warp(day4);
        vm.prank(beneficiary);
        staking.claim(1);

        vm.prank(staker2);
        staking.claim(2);
        
        uint256 finalStaker1Balance = wdia.balanceOf(staker);
        uint256 finalStaker2Balance = wdia.balanceOf(staker2);

        uint256 staker1Rewards = finalStaker1Balance - initialStaker1Balance;
        uint256 staker2Rewards = finalStaker2Balance - initialStaker2Balance;   
        
        console2.log("Staker 1 rewards:", formatAmount(staker1Rewards));
        console2.log("Staker 2 rewards:", formatAmount(staker2Rewards));
        
        uint256 staker1ExpectedRewards = (STAKING_AMOUNT * 4000) / 10000;
        uint256 staker2ExpectedRewards = (STAKING_AMOUNT * 2000) / 10000; 

        console2.log("\nRewards Comparison Test Results:");
        console2.log("Staker 1 (stakeForAddress):");
        console2.log("- Rewards Received:", formatAmount(staker1Rewards));
        console2.log("- Expected Rewards:", formatAmount(staker1ExpectedRewards));

        console2.log("\nStaker 2 (stake):");
        console2.log("- Rewards Received:", formatAmount(staker2Rewards));
        console2.log("- Expected Rewards:", formatAmount(staker2ExpectedRewards));

        // Verify rewards
        assertEq(staker1Rewards, staker1ExpectedRewards, "Staker 1 should receive correct rewards");
        assertEq(staker2Rewards, staker2ExpectedRewards, "Staker 2 should receive correct rewards");                                            
    }

    function test_requestClaimPeriod() public {
        uint256 nearEndOfDay4 = 431700; // 4.99 days --> earn 0.8 tokens
        uint256 day5 = 432001; // 5.0 days --> earn 0.2 tokens

        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stake(STAKING_AMOUNT); // 100% to principal wallet
        vm.stopPrank();

        // Advance time by 5 days to accumulate rewards
        vm.warp(nearEndOfDay4);

        // Get initial balances
        uint256 initialStakerBalance = wdia.balanceOf(staker);

        // Claim rewards near the end of day 4
        vm.prank(staker);
        staking.claim(1);

        // Get balances after claiming rewards
        uint256 afterClaimStakerBalance = wdia.balanceOf(staker);

        // Calculate reward amounts
        uint256 stakerReward = afterClaimStakerBalance - initialStakerBalance;

        // Advance time by 1 second to simulate block timing
        // This puts us in the next day, causing totalRewards to be greater than paidOutReward
        vm.warp(day5);
        // uint256 remainingRewards = staking.getRemainingRewards(1);
        // console2.log("remainingRewards", remainingRewards);

        // Try to request unstake - this should fail due to the paidOutReward check
        vm.prank(staker);
        // vm.expectRevert(UnclaimedRewards.selector);
        staking.requestUnstake(1);
        uint256 remainingRewards = staking.getRemainingRewards(1);
        uint256 expectedRewards = (STAKING_AMOUNT * 2000) / 10000;

        assertEq(remainingRewards, expectedRewards, "Should receive 0 rewards after unstaking request");


        // Log the results
        // console2.log("\nRequest Unstake Timing Test Results:");
        // console2.log("Initial Staker Balance:", formatAmount(initialStakerBalance));
        // console2.log("After Claim Staker Balance:", formatAmount(afterClaimStakerBalance));
        // console2.log("Staker Rewards:", formatAmount(stakerReward));
    }

    function test_RewardsDuringUnstakingPeriod() public {
        uint256 day5 = 432001;

        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        // Advance time by 5 days
        vm.warp(day5);

        // Get initial balances
        uint256 initialStakerBalance = wdia.balanceOf(staker);
        uint256 beforeClaimRewards = staking.getTotalRewards(1);

        // Request unstake
        vm.startPrank(beneficiary);
        staking.claim(1);
        staking.requestUnstake(1);
        vm.stopPrank();

        // Get final balance
        uint256 finalStakerBalance = wdia.balanceOf(staker);
        uint256 rewardsBeforeUnstaking = finalStakerBalance - initialStakerBalance;

        // Expected rewards for 3 days during unstaking period
        uint256 expectedRewards = (STAKING_AMOUNT * 10000) / 10000;

        assertEq(rewardsBeforeUnstaking, STAKING_AMOUNT, "Should receive rewards during unstaking period");

        // Advance time by 1 day during unstaking period
        uint256 day6 = day5 + SECONDS_IN_A_DAY;
        vm.warp(day6);
        
        // Check if rewards are still accruing
        uint256 afterClaimRewards = staking.getTotalRewards(1);

        assertEq(afterClaimRewards, STAKING_AMOUNT, "Should receive 0 rewards during unstaking period");

    }

    function test_RequestWithPendingRewards() public {
        uint256 day5 = 432001;

        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        // Advance time by 5 days
        vm.warp(day5);

        // Get initial balances
        uint256 initialStakerBalance = wdia.balanceOf(staker);
        uint256 beforeClaimRewards = staking.getTotalRewards(1);

        // Request unstake
        vm.prank(beneficiary);
        staking.requestUnstake(1);

        // Advance time by 2 days and claim rewards
        uint256 day7 = day5 + (SECONDS_IN_A_DAY * 2);
        vm.warp(day7);
        vm.prank(beneficiary);
        staking.claim(1);

        // Get final balance
        uint256 finalStakerBalance = wdia.balanceOf(staker);
        uint256 rewardsAfterUnstakingRequest = finalStakerBalance - initialStakerBalance;
        uint256 expectedRewards = (STAKING_AMOUNT * 10000) / 10000;

        assertEq(rewardsAfterUnstakingRequest, expectedRewards, "Should receive 1 rewards after unstaking request");

        uint256 totalRewards = staking.getTotalRewards(1);
        assertEq(totalRewards, expectedRewards, "Should receive 0 rewards after unstaking request");

        uint256 remainingRewards = staking.getRemainingRewards(1);
        assertEq(remainingRewards, 0, "Should receive 0 rewards after unstaking request");
    }

    // 1. request unstake without ever claiming before
    // 2. unstake without claim
    // 3. call getTotalRewards(), getRemainingRewards() and see if they return pending rewards as the total
    function test_UnstakeWithoutClaiming() public {
        uint256 day5 = 432001;

        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();

        // Get initial balances
        uint256 BeforeStakerBalance = wdia.balanceOf(staker);
        uint256 beforeClaimRewards = staking.getTotalRewards(1);

        // Request unstake
        vm.warp(day5);
        vm.prank(beneficiary);
        staking.requestUnstake(1);

        // Advance time by 7 days (unstaking period)
        uint256 day7 = day5 + (SECONDS_IN_A_DAY * 7);
        vm.warp(day7);

        vm.prank(staker);
        staking.unstake(1);

        // Get final balance
        uint256 AfterStakerBalance = wdia.balanceOf(staker);
        uint256 BalanceDifference = AfterStakerBalance - BeforeStakerBalance;

        assertEq(BalanceDifference, STAKING_AMOUNT, "Should unstake all principal");

        uint256 totalRewards = staking.getTotalRewards(1);
        uint256 remainingRewards = staking.getRemainingRewards(1);

        assertEq(totalRewards, STAKING_AMOUNT, "Should receive 1 token rewards after unstaking request");
        assertEq(remainingRewards, STAKING_AMOUNT, "Should receive 1 token rewards after unstaking request");

        vm.prank(beneficiary);
        staking.claim(1);

        uint256 expectedRewards = (STAKING_AMOUNT * 10000) / 10000;
        AfterStakerBalance = wdia.balanceOf(staker);
        uint256 rewardsAfterClaim = AfterStakerBalance - (2 * 1e18);

        assertEq(rewardsAfterClaim, expectedRewards, "Should receive 1 token rewards after unstaking request");
    }

    function test_DoubleClaim() public {
        uint256 day5 = 432001;

        // Setup initial stake
        vm.startPrank(staker);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000); // 100% to principal wallet
        vm.stopPrank();
        // Get initial balances
        uint256 BeforeStakerBalance = wdia.balanceOf(staker);
        uint256 beforeClaimRewards = staking.getTotalRewards(1);

        // Request unstake
        vm.warp(day5);
        vm.prank(beneficiary);
        staking.requestUnstake(1);

        // Advance time by 7 days (unstaking period)
        uint256 day7 = day5 + (SECONDS_IN_A_DAY * 7);
        vm.warp(day7);

        vm.startPrank(staker);
        staking.unstake(1);
        staking.requestUnstake(1);
        vm.stopPrank();

        uint256 totalRewards = staking.getTotalRewards(1);
        uint256 remainingRewards = staking.getRemainingRewards(1);

        assertEq(totalRewards, STAKING_AMOUNT, "Should receive 1 token rewards after unstaking request");
        assertEq(remainingRewards, STAKING_AMOUNT, "Should receive 1 token rewards after unstaking request");

        uint256 day8 = day7 + (SECONDS_IN_A_DAY);
        vm.warp(day8);
        vm.prank(beneficiary);
        staking.claim(1);

        uint256 expectedRewards = (STAKING_AMOUNT * 10000) / 10000;
        uint256 AfterStakerBalance = wdia.balanceOf(staker);
        uint256 rewardsAfterClaim = AfterStakerBalance - (2 * 1e18);

        assertEq(rewardsAfterClaim, expectedRewards, "Should receive 1 token rewards after unstaking request"); 

        uint256 day9 = day8 + SECONDS_IN_A_DAY;
        vm.warp(day9);
        vm.prank(beneficiary);
        staking.claim(1);

        uint256 expectedRewards2 = 0;
        AfterStakerBalance = wdia.balanceOf(staker);
        uint256 rewardsAfterClaim2 = AfterStakerBalance - (3 * 1e18);

        assertEq(rewardsAfterClaim2, expectedRewards2, "Should receive 1 token rewards after unstaking request"); 
    }

} 