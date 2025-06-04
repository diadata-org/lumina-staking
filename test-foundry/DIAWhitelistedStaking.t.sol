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

 

 
    
} 