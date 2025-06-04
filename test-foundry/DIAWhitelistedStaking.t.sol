// SPDX-License-Identifier: GPL
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DIAWhitelistedStaking} from "../contracts/DIAWhitelistedStaking.sol";
import {WDIA} from "../contracts/WDIA.sol";

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

    function test_RewardsTable() public {
        // Setup second user

        console2.log("balance of rewards wallet", wdia.balanceOf(rewardsWallet));
        console2.log("balance of staker", wdia.balanceOf(staker));
        console2.log("balance of beneficiary", wdia.balanceOf(beneficiary));

        address staker2 = makeAddr("staker2");
        address beneficiary2 = makeAddr("beneficiary2");
        
        // Fund second staker
        vm.deal(staker2, 10000 * 1e18);
        
        // Add second user to whitelist
        vm.startPrank(owner);
        staking.addWhitelistedStaker(staker2);
        staking.addWhitelistedStaker(beneficiary2);
        vm.stopPrank();

        // Fund second staker with WDIA tokens
        vm.startPrank(staker2);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        // Stake for first user
        vm.startPrank(staker);
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 900); // 90% to principal wallet
        vm.stopPrank();

        // Stake for second user
        vm.startPrank(staker2);
        staking.stakeForAddress(beneficiary2, STAKING_AMOUNT, 1000); // 100% to principal wallet
        vm.stopPrank();

        uint256 stakingStoreIndex1 = 1;
        uint256 stakingStoreIndex2 = 2;
        
        // Print header for first user
        console2.log("\nRewards Table for User 1 (90/10 split)");
        console2.log("Initial Stake: 1000 WDIA");
        console2.log("Daily Reward Rate: 20% (2000 basis points)");
        console2.log("Days | Principal WDIA | Total WDIA Rewards | Principal WDIA | Beneficiary WDIA | Total DIA Value");
        console2.log("-----|---------------|-------------------|----------------|------------------|----------------");

        // Calculate and display rewards for different time periods for first user
        for (uint256 dayCount = 1; dayCount <= 10; dayCount++) {
            // Advance time
            vm.warp(block.timestamp + 25 days);

            // Claim rewards
            vm.prank(beneficiary);
            staking.claim(stakingStoreIndex1);

            // Get balances after claiming
            uint256 principalBalance = wdia.balanceOf(staker);
            uint256 beneficiaryBalance = wdia.balanceOf(beneficiary);
            uint256 totalRewards = principalBalance + beneficiaryBalance;

            // Fund staker with more WDIA tokens
            vm.startPrank(staker);
            vm.deal(staker, STAKING_AMOUNT);
            wdia.deposit{value: STAKING_AMOUNT}();
            wdia.approve(address(staking), STAKING_AMOUNT);
            staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 10000);
            vm.stopPrank();


            // Print row with 4 decimal places
            console2.log(
                string.concat(
                    vm.toString(dayCount),
                    " | ",
                    formatAmount(STAKING_AMOUNT),
                    " WDIA | ",
                    formatAmount(totalRewards),
                    " WDIA | ",
                    formatAmount(principalBalance),
                    " WDIA | ",
                    formatAmount(beneficiaryBalance),
                    " WDIA | ",
                    formatAmount(totalRewards),
                    " DIA"
                )
            );
        }

        // Reset balances for second user
        vm.startPrank(staker2);
        uint256 staker2Balance = wdia.balanceOf(staker2);
        if (staker2Balance > 0) {
            wdia.withdraw(staker2Balance);
        }
        vm.deal(staker2, STAKING_AMOUNT);
        wdia.deposit{value: STAKING_AMOUNT}();
        wdia.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(beneficiary2);
        uint256 beneficiary2Balance = wdia.balanceOf(beneficiary2);
        if (beneficiary2Balance > 0) {
            wdia.withdraw(beneficiary2Balance);
        }
        vm.stopPrank();

        // Print header for second user
        console2.log("\nRewards Table for User 2 (100/0 split)");
        console2.log("Initial Stake: 1000 WDIA");
        console2.log("Daily Reward Rate: 20% (2000 basis points)");
        console2.log("Days | Principal WDIA | Total WDIA Rewards | Staker  | Beneficiary  | Total DIA Value");
        console2.log("-----|---------------|-------------------|----------------|------------------|----------------");

        // Calculate and display rewards for different time periods for second user
        for (uint256 dayCount = 1; dayCount <= 10; dayCount++) {
            // Advance time
            vm.warp(block.timestamp + 25 days);

            // Claim rewards
            vm.prank(beneficiary2);
            staking.claim(stakingStoreIndex2);

            // Get balances after claiming
            uint256 principalBalance = wdia.balanceOf(staker2);
            uint256 beneficiaryBalance = wdia.balanceOf(beneficiary2);
            uint256 totalRewards = principalBalance + beneficiaryBalance;

            // Fund staker with more WDIA tokens
            vm.startPrank(staker2);
            vm.deal(staker2, STAKING_AMOUNT);
            wdia.deposit{value: STAKING_AMOUNT}();
            wdia.approve(address(staking), STAKING_AMOUNT);
            staking.stakeForAddress(beneficiary2, STAKING_AMOUNT, 10000);
            vm.stopPrank();

            // Print row with 4 decimal places
            console2.log(
                string.concat(
                    vm.toString(dayCount),
                    " | ",
                    formatAmount(STAKING_AMOUNT),
                    " WDIA | ",
                    formatAmount(totalRewards),
                    " WDIA | ",
                    formatAmount(principalBalance),
                    " WDIA | ",
                    formatAmount(beneficiaryBalance),
                    " WDIA | ",
                    formatAmount(totalRewards),
                    " DIA"
                )
            );
        }

        // Print summary
        console2.log("\nSummary:");
        console2.log("User 1 (90/10 split):");
        console2.log("- Initial Stake: 1000 WDIA");
        console2.log("- Final Principal Balance: ", vm.toString(wdia.balanceOf(staker) / 1e18), " WDIA");
        console2.log("- Final Beneficiary Balance: ", vm.toString(wdia.balanceOf(beneficiary) / 1e18), " WDIA");
        console2.log("- Total Rewards: ", vm.toString((wdia.balanceOf(staker) + wdia.balanceOf(beneficiary)) / 1e18), " WDIA");

        console2.log("\nUser 2 (100/0 split):");
        console2.log("- Initial Stake: 1000 WDIA");
        console2.log("- Final Principal Balance: ", vm.toString(wdia.balanceOf(staker2) / 1e18), " WDIA");
        console2.log("- Final Beneficiary Balance: ", vm.toString(wdia.balanceOf(beneficiary2) / 1e18), " WDIA");
        console2.log("- Total Rewards: ", vm.toString((wdia.balanceOf(staker2) + wdia.balanceOf(beneficiary2)) / 1e18), " WDIA");
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
        staking.stakeForAddress(beneficiary, STAKING_AMOUNT, 900); // 90% to principal wallet
        vm.stopPrank();

        uint256 stakingStoreIndex = 1;

        // Advance time by 7 days
        vm.warp(block.timestamp + 7 days);

        // Claim rewards
        vm.prank(beneficiary);
        staking.claim(stakingStoreIndex);

        // Request unstake
        vm.prank(beneficiary);
        staking.requestUnstake(stakingStoreIndex);

        // Advance time by unstaking duration
        vm.warp(block.timestamp + UNSTAKING_DURATION);

        // Unstake
        vm.prank(staker);
        staking.unstake(stakingStoreIndex);

        // Calculate expected rewards
        uint256 expectedTotalReward = (STAKING_AMOUNT * REWARD_RATE_PER_DAY * 7) / 10000; // 20% per day for 7 days
        uint256 expectedPrincipalShare = (expectedTotalReward * 900) / 10000; // 90% of reward
        uint256 expectedBeneficiaryShare = expectedTotalReward - expectedPrincipalShare; // 10% of reward

        // Check balances
        assertEq(wdia.balanceOf(staker), STAKING_AMOUNT + expectedPrincipalShare, "Principal wallet should receive principal plus 90% of rewards");
        assertEq(wdia.balanceOf(beneficiary), expectedBeneficiaryShare, "Beneficiary should receive 10% of rewards");
    }
} 