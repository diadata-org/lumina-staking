// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../contracts/DIAExternalStaking.sol";
import "../contracts/DIARewardsDistribution.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/DIAStakingCommons.sol";


// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Test contract for DIAExternalStaking
contract DIAExternalStakingTest is Test {
    DIAExternalStaking stakingContract;
    IERC20 stakingToken;
    address owner = address(this);
    address user = address(0x123);
    address rewardsWallet = address(0x124);

    uint256 constant STAKE_AMOUNT = 100 * 10 ** 18;
    uint256 constant INITIAL_USER_BALANCE = 1000 * 10 ** 18;
    uint256 constant INITIAL_CONTRACT_BALANCE = 1000 * 10 ** 18;

    uint256 constant STAKING_LIMIT = 100000000 * 10 ** 18;

    // Setup function for initializing contracts and balances
    function setUp() public {
        stakingToken = IERC20(address(new MockERC20("TestToken", "TT", 18)));
        stakingContract = new DIAExternalStaking(
            3 days,
            address(stakingToken),
            rewardsWallet,
            100,
            STAKING_LIMIT
        );

        stakingContract.setDailyWithdrawalThreshold(1);

        deal(address(stakingToken), user, INITIAL_USER_BALANCE);
        deal(address(stakingToken), rewardsWallet, 10000000 * 10 ** 18);
        deal(
            address(stakingToken),
            address(stakingContract),
            INITIAL_CONTRACT_BALANCE
        );
        deal(address(stakingToken), owner, INITIAL_USER_BALANCE);

        vm.startPrank(rewardsWallet);
        stakingToken.approve(address(stakingContract), 10000000 * 10 ** 18);
    }

    // Helper function to stake tokens
    function stakeTokens(uint256 amount) internal {
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), amount);
        stakingContract.stake(amount, 0);
        vm.stopPrank();
    }

    function stakeForTokens(uint256 amount, address user) internal {
        vm.startPrank(owner);

        stakingToken.approve(address(stakingContract), amount);
        console.log("stakeforaddress");

        stakingContract.stakeForAddress(user, amount, 0);
        vm.stopPrank();
    }

    // Test staking functionality
    function testStake() public {
        uint256 initialUserBalance = stakingToken.balanceOf(user);
        uint256 initialContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        stakeTokens(STAKE_AMOUNT);

        uint256 finalUserBalance = stakingToken.balanceOf(user);
        uint256 finalContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        // Ensure balances are updated correctly
        assertEq(
            finalContractBalance,
            initialContractBalance + STAKE_AMOUNT,
            "Contract balance should increase"
        );
        assertEq(
            finalUserBalance,
            initialUserBalance - STAKE_AMOUNT,
            "User balance should decrease"
        );

        // Verify staking store
        (address beneficiary, , , uint256 principal, , , , ,,,) = stakingContract
            .stakingStores(1);
        assertEq(beneficiary, user, "Beneficiary should match the user");
        assertEq(
            principal,
            STAKE_AMOUNT,
            "Principal should match the staked amount"
        );
    }

    // Test request unstake
    function testRequestUnstake() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        (, , , , , , uint256 unstakingRequestTime, ,,,) = stakingContract
            .stakingStores(1);
        console.log("Unstaking request time:", unstakingRequestTime);
        // Uncomment and assert if necessary
        // assertGt(unstakingRequestTime, 0, "Unstaking request time should be greater than 0");
    }

    // Test unstake functionality
    function testUnstake() public {
        // Pre-stake and request unstake
        stakeTokens(STAKE_AMOUNT);
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Simulate time passing (4 days)
        vm.warp(block.timestamp + 4 days);

        (
            ,
            ,
            ,
            uint256 principal,
            ,
            ,
            uint256 unstakingRequestTime,
            ,
            ,
            ,

        ) = stakingContract.stakingStores(1);

        // Perform unstake and check balances
        stakingContract.unstake(1, principal);
        vm.stopPrank();

        // Verify reward is zero after unstake (no rewards accumulated in this test)
        (, , , , uint256 reward, , , ,,,) = stakingContract.stakingStores(1);
        assertEq(reward, 0, "Reward should be zero after unstaking");
    }

    // Test reward accumulation over time (simulated)
    function testRewardAccumulation() public {
        stakeTokens(STAKE_AMOUNT);

        // Simulate 5 days passing
        vm.warp(block.timestamp + 5 days);

        // Calculate expected reward (stubbed for now)
        // uint256 expectedReward = (100 * 10 ** 18 * (rewardRatePerDay ** 5)) / 1e10;
        // uint256 actualReward = stakingContract.getRewardForStakingStore(1);
        // assertApproxEqRel(actualReward, expectedReward, 0.01e18); // Allowing small precision error
    }

    // Test if unstaking fails before the required period
    function testUnstakeBeforePeriodFails() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Fast-forward time by 2 days (not enough to unstake)
        vm.warp(block.timestamp + 2 days);
        (
            ,
            ,
            ,
            uint256 principal,
            ,
            ,
            uint256 unstakingRequestTime,
            ,
            ,
            ,

        ) = stakingContract.stakingStores(1);

        vm.expectRevert(UnstakingPeriodNotElapsed.selector);

        stakingContract.unstake(1, principal);
    }

    // Test if unstaking without requesting fails
    function testUnstakeWithoutRequestFails() public {
        testStake();
        vm.startPrank(user);
        (
            ,
            ,
            ,
            uint256 principal,
            ,
            ,
            uint256 unstakingRequestTime,
            ,
            ,
            ,

        ) = stakingContract.stakingStores(1);

        // Attempt unstake without requesting
        vm.expectRevert(UnstakingNotRequested.selector);

        stakingContract.unstake(1, principal);
    }

    function testOwnerCanSetPrincipalUnstaker() public {
        stakeTokens(STAKE_AMOUNT);

        vm.startPrank(user);
        stakingContract.updatePrincipalUnstaker(user, 1);
        vm.stopPrank();

        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 reward,
            uint256 stakingStartTime,
            uint256 unstakingRequestTime,
            ,
            ,
            ,

        ) = stakingContract.stakingStores(1);

        assertEq(
            principalUnstaker,
            user,
            "Principal unstaker should be set by the owner."
        );
    }

    function testOnlyPrincipalUnstakerCanUpdate() public {
        stakeForTokens(STAKE_AMOUNT, user);

        // Owner sets the initial principal unstaker
        vm.startPrank(owner);
        stakingContract.updatePrincipalUnstaker(user, 1);
        vm.stopPrank();

        // The initial unstaker (user) successfully updates it to another address
        vm.startPrank(user);

        stakingContract.updatePrincipalUnstaker(address(0x5678), 1);
        vm.stopPrank();

        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 reward,
            uint256 stakingStartTime,
            uint256 unstakingRequestTime,
            ,
            ,
            ,

        ) = stakingContract.stakingStores(1);

        assertEq(
            principalUnstaker,
            address(0x5678),
            "Principal unstaker should be updated by the previous unstaker."
        );
    }

    // Test full stake and unstake flow with reward validation
    function testFullStakeAndUnstake() public {
        // Stake tokens
        testStake();

        // Start by requesting unstake
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Simulate 4 days passing (reward accumulation happens during this period)
        vm.warp(block.timestamp + 4 days);

        // Store the current reward balance before unstaking
        uint256 rewardBeforeUnstake = stakingContract.getRewardForStakingStore(
            1
        );

        (
            ,
            ,
            ,
            uint256 principal,
            ,
            ,
            uint256 unstakingRequestTime,
            ,
            ,
            ,

        ) = stakingContract.stakingStores(1);

        // Unstake tokens
        stakingContract.unstake(1, principal);
        vm.stopPrank();

        // Verify user balance is restored after unstake

        assertEq(
            stakingToken.balanceOf(user),
            INITIAL_USER_BALANCE + rewardBeforeUnstake,
            "User balance should be restored after unstake"
        );

        // Verify that the reward is non-zero and has been distributed correctly
        uint256 rewardAfterUnstake = stakingContract.getRewardForStakingStore(
            1
        );
        assertEq(
            rewardAfterUnstake,
            0,
            "Reward should be paid out upon unstaking"
        );

        // If rewards were accumulated, ensure the user received the reward amount
        uint256 finalUserBalance = stakingToken.balanceOf(user);
        uint256 expectedUserBalance = INITIAL_USER_BALANCE +
            rewardBeforeUnstake;
        console.log("finalUserBalance", finalUserBalance);

        assertEq(
            finalUserBalance,
            expectedUserBalance,
            "User balance should include the staked amount and accumulated rewards"
        );
    }

    function testStakeBelowMinimumFails() public {
        uint256 belowMinimumStake = 1 * 10 ** 17;

        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), belowMinimumStake);

        vm.expectRevert(
            abi.encodeWithSelector(
                AmountBelowMinimumStake.selector,
                belowMinimumStake
            )
        );

        stakingContract.stake(belowMinimumStake, 0);

        vm.stopPrank();
    }

    function testRequestUnstake_NotBeneficiaryFails() public {
        testStake();

        address nonBeneficiary = address(0x5678);

        vm.startPrank(nonBeneficiary);
        vm.expectRevert(AccessDenied.selector);
        stakingContract.requestUnstake(1);
        vm.stopPrank();
    }

    function testRequestUnstake_AlreadyRequestedUnstakeFails() public {
        testStake();

        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        vm.expectRevert(AlreadyRequestedUnstake.selector);
        stakingContract.requestUnstake(1);
        vm.stopPrank();
    }

    function testRequestUnstakeWithBalanceCheck() public {
        testStake();
        vm.startPrank(user);

        // Get initial balance before requesting unstake
        uint256 userBalanceBefore = stakingToken.balanceOf(user);
        uint256 contractBalanceBefore = stakingToken.balanceOf(
            address(stakingContract)
        );

        // Request unstake
        stakingContract.requestUnstake(1);

        // Get balance after requesting unstake (should remain the same)
        uint256 userBalanceAfter = stakingToken.balanceOf(user);
        uint256 contractBalanceAfter = stakingToken.balanceOf(
            address(stakingContract)
        );

        // Fetch unstaking request time
        (, , , , , , uint256 unstakingRequestTime, ,,,) = stakingContract
            .stakingStores(1);
        console.log("Unstaking request time:", unstakingRequestTime);

        // Assert unstaking request time is greater than zero
        assertGt(
            unstakingRequestTime,
            0,
            "Unstaking request time should be greater than 0"
        );

        // Ensure that balances remain unchanged since unstaking hasn't happened yet
        assertEq(
            userBalanceBefore,
            userBalanceAfter,
            "User balance should remain unchanged after unstake request"
        );
        assertEq(
            contractBalanceBefore,
            contractBalanceAfter,
            "Contract balance should remain unchanged after unstake request"
        );

        vm.stopPrank();
    }

    function testUnstakeTwiceFails() public {
        // Stake tokens and request unstake
        testStake();
        vm.startPrank(user);

        uint256 userBalanceBeforeUnstake = stakingToken.balanceOf(user);
        uint256 contractBalanceBeforeUnstake = stakingToken.balanceOf(
            address(stakingContract)
        );

        stakingContract.requestUnstake(1);

        // Simulate time passing (after the unstaking period)
        vm.warp(block.timestamp + 4 days);

        uint256 rewardBeforeUnstake = stakingContract.getRewardForStakingStore(
            1
        );
        // First unstake should succeed
        (
            ,
            ,
            ,
            uint256 principal,
            ,
            ,
            uint256 unstakingRequestTime,
            ,
            ,
            ,

        ) = stakingContract.stakingStores(1);

        stakingContract.unstake(1, principal);

        // Verify user balance is restored after the first unstake
        uint256 userBalanceAfterFirstUnstake = stakingToken.balanceOf(user);
        uint256 contractBalanceAfterFirstUnstake = stakingToken.balanceOf(
            address(stakingContract)
        );

        assertEq(
            userBalanceAfterFirstUnstake,
            userBalanceBeforeUnstake + STAKE_AMOUNT + rewardBeforeUnstake,
            "User balance should increase after first unstake"
        );
        assertLt(
            contractBalanceAfterFirstUnstake,
            contractBalanceBeforeUnstake,
            "Contract balance should decrease after first unstake"
        );

        // Store balance before second unstake attempt
        uint256 userBalanceBeforeSecondUnstake = stakingToken.balanceOf(user);
        (, , , principal, , , unstakingRequestTime, ,,,) = stakingContract
            .stakingStores(1);

        // Second unstake attempt should fail
        vm.expectRevert(UnstakingNotRequested.selector);

        stakingContract.unstake(1, principal);

        // User balance should remain unchanged after failed unstake attempt
        uint256 userBalanceAfterSecondUnstake = stakingToken.balanceOf(user);
        assertEq(
            userBalanceAfterSecondUnstake,
            userBalanceBeforeSecondUnstake,
            "User balance should remain the same after failed second unstake"
        );

        vm.stopPrank();
    }

    // function testUnstakeExceedAmount() public {
    //     uint256 exceededAmount = STAKE_AMOUNT + 100 * 10;
    //     // Stake tokens and request unstake
    //     testStake();
    //     vm.startPrank(user);

    //     uint256 userBalanceBeforeUnstake = stakingToken.balanceOf(user);
    //     uint256 contractBalanceBeforeUnstake = stakingToken.balanceOf(
    //         address(stakingContract)
    //     );

    //     stakingContract.requestUnstake(1);

    //     // Simulate time passing (after the unstaking period)
    //     vm.warp(block.timestamp + 4 days);

    //     uint256 rewardBeforeUnstake = stakingContract.getRewardForStakingStore(
    //         1
    //     );
    //     // First unstake should succeed
    //     (
    //         ,
    //         ,
    //         ,
    //         uint256 principal,
    //         ,
    //         ,
    //         uint256 unstakingRequestTime,

    //     ) = stakingContract.stakingStores(1);


    //     vm.expectRevert(DIAExternalStaking.AmountExceedsStaked.selector);
    //     stakingContract.unstake(1, exceededAmount);
  
    // }

    function testUnstakePartial() public {
        uint256 PARTIAL_UNSTAKE_AMOUNT = 100;
        // Stake tokens and request unstake
        testStake();
        vm.startPrank(user);

        uint256 userBalanceBeforeUnstake = stakingToken.balanceOf(user);
        uint256 contractBalanceBeforeUnstake = stakingToken.balanceOf(
            address(stakingContract)
        );

        stakingContract.requestUnstake(1);

        // Simulate time passing (after the unstaking period)
        vm.warp(block.timestamp + 4 days);

        uint256 rewardBeforeUnstake = stakingContract.getRewardForStakingStore(
            1
        );
        // First unstake should succeed
        (
            ,
            ,
            ,
            uint256 principal,
            ,
            ,
            uint256 unstakingRequestTime,
            ,
            ,
            ,

        ) = stakingContract.stakingStores(1);

        stakingContract.unstake(1, PARTIAL_UNSTAKE_AMOUNT);
        vm.warp(block.timestamp + 4 days);

        stakingContract.requestUnstake(1);

        // Verify user balance is restored after the first unstake
        uint256 userBalanceAfterFirstUnstake = stakingToken.balanceOf(user);
        uint256 contractBalanceAfterFirstUnstake = stakingToken.balanceOf(
            address(stakingContract)
        );

        console.log(
            "userBalanceAfterFirstUnstake",
            userBalanceAfterFirstUnstake
        );
        console.log("userBalanceBeforeUnstake", userBalanceBeforeUnstake);

        console.log("rewardBeforeUnstake", rewardBeforeUnstake);
        console.log("STAKE_AMOUNT", STAKE_AMOUNT);

        console.log(
            "userBalanceBeforeUnstake + PARTIAL_UNSTAKE_AMOUNT + rewardBeforeUnstake",
            userBalanceBeforeUnstake +
                PARTIAL_UNSTAKE_AMOUNT +
                rewardBeforeUnstake
        );

        assertEq(
            userBalanceAfterFirstUnstake,
            userBalanceBeforeUnstake +
                PARTIAL_UNSTAKE_AMOUNT +
                rewardBeforeUnstake,
            "User balance should increase after first unstake"
        );
        assertLt(
            contractBalanceAfterFirstUnstake,
            contractBalanceBeforeUnstake,
            "Contract balance should decrease after first unstake"
        );

        // Store balance before second unstake attempt
        uint256 userBalanceBeforeSecondUnstake = stakingToken.balanceOf(user);

        // Second unstake attempt should fail
        // vm.expectRevert(DIAExternalStaking.AlreadyUnstaked.selector);
        (, , , principal, , , unstakingRequestTime, ,,,) = stakingContract
            .stakingStores(1);

        vm.warp(block.timestamp + 8 days);
        rewardBeforeUnstake = stakingContract.getRewardForStakingStore(1);

        stakingContract.unstake(1, principal);

        // User balance should remain unchanged after failed unstake attempt
        uint256 userBalanceAfterSecondUnstake = stakingToken.balanceOf(user);
        assertEq(
            userBalanceAfterSecondUnstake,
            userBalanceBeforeUnstake + STAKE_AMOUNT + rewardBeforeUnstake,
            "User balance should remain the same after failed second unstake"
        );

        vm.stopPrank();
    }

    function testUpdatePrincipalPayoutWallet() public {
        stakeTokens(STAKE_AMOUNT);

        address newPayoutWallet = address(0x9876);

        // Ensure only the principal unstaker can update
        vm.startPrank(user);
        stakingContract.updatePrincipalPayoutWallet(newPayoutWallet, 1);
        vm.stopPrank();

        (, address principalPayoutWallet, , , , , , ,,,) = stakingContract
            .stakingStores(1);

        assertEq(
            principalPayoutWallet,
            newPayoutWallet,
            "Principal payout wallet should be updated correctly."
        );
    }

    function testSetUnstakingDuration() public {
        uint256 newDuration = 7 days;

        vm.startPrank(owner);
        stakingContract.setUnstakingDuration(newDuration);
        vm.stopPrank();

        // Verify the unstaking duration was updated correctly
        assertEq(
            stakingContract.unstakingDuration(),
            newDuration,
            "Unstaking duration should be updated to new value"
        );
    }

    function testSetUnstakingDurationTooShortFails() public {
        uint256 shortDuration = 12 hours; // Less than 1 day

        vm.startPrank(owner);
        vm.expectRevert(UnstakingDurationTooShort.selector);
        stakingContract.setUnstakingDuration(shortDuration);
        vm.stopPrank();
    }

    function testSetUnstakingDurationTooLongFails() public {
        uint256 longDuration = 21 days; // More than 20 days

        vm.startPrank(owner);
        vm.expectRevert(UnstakingDurationTooLong.selector);
        stakingContract.setUnstakingDuration(longDuration);
        vm.stopPrank();
    }

    function testNonOwnerCannotSetUnstakingDuration() public {
        uint256 newDuration = 7 days;
        address nonOwner = address(0x5678);

        vm.startPrank(nonOwner);
        vm.expectRevert();
        stakingContract.setUnstakingDuration(newDuration);
        vm.stopPrank();
    }

    function testOnlyPrincipalUnstakerCanUpdatePayoutWallet() public {
        stakeForTokens(STAKE_AMOUNT, user);

        // Owner sets the initial principal unstaker
        vm.startPrank(owner);
        stakingContract.updatePrincipalUnstaker(user, 1);
        vm.stopPrank();

        address newPayoutWallet = address(0x9876);

        // A non-principal unstaker should fail to update the payout wallet
        vm.startPrank(address(0x5678));
        vm.expectRevert(NotPrincipalUnstaker.selector);
        stakingContract.updatePrincipalPayoutWallet(newPayoutWallet, 1);
        vm.stopPrank();
    }

    function testSplitStakeAndUnstakeExternal() public {
        address delegator = address(0x345);
        deal(address(stakingToken), delegator, INITIAL_USER_BALANCE);

        uint256 start = block.timestamp;

        // Stake tokens
        uint256 initialUserBalance = stakingToken.balanceOf(user);
        uint256 initialDelegatorBalance = stakingToken.balanceOf(user);

        uint256 initialContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        // stakeTokens(STAKE_AMOUNT);

        vm.startPrank(delegator);
        stakingToken.approve(address(stakingContract), STAKE_AMOUNT);
        stakingContract.stakeForAddress(user, STAKE_AMOUNT, 400); // Principal wallet gets 4% reward

        vm.stopPrank();

        uint256 finalUserBalance = stakingToken.balanceOf(delegator);
        uint256 finalContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        // Ensure balances are updated correctly
        assertEq(
            finalContractBalance,
            initialContractBalance + STAKE_AMOUNT,
            "Contract balance should increase"
        );
        assertEq(
            finalUserBalance,
            initialDelegatorBalance - STAKE_AMOUNT,
            "User balance should decrease"
        );

        // Verify staking store
        (address beneficiary, , , uint256 principal, , , , ,,,) = stakingContract
            .stakingStores(1);
        assertEq(beneficiary, user, "Beneficiary should match the user");
        assertEq(
            principal,
            STAKE_AMOUNT,
            "Principal should match the staked amount"
        );

        vm.warp(start + 4 days);

        // Start by requesting unstake
        vm.startPrank(delegator);

        stakingContract.requestUnstake(1);

        // Simulate 4 days passing (reward accumulation happens during this period)
        vm.warp(start + 8 days);

        // Store the current reward balance before unstaking
        uint256 rewardBeforeUnstake = stakingContract.getRewardForStakingStore(
            1
        );

        console.log("Total Rewards", rewardBeforeUnstake);

        uint256 userRewards = ((rewardBeforeUnstake * 96) / 100); // 96% of rewards

        console.log("96% Rewards", userRewards);

        (, , , principal, , , ,, ,,) = stakingContract.stakingStores(1);

        // Unstake tokens
        stakingContract.unstake(1, principal);
        vm.stopPrank();

        // Verify user balance is restored after unstake

        assertEq(
            stakingToken.balanceOf(user),
            INITIAL_USER_BALANCE + userRewards,
            "User balance should be restored after unstake"
        );

        // Verify that the reward is non-zero and has been distributed correctly
        uint256 rewardAfterUnstake = stakingContract.getRewardForStakingStore(
            1
        );
        assertEq(
            rewardAfterUnstake,
            0,
            "Reward should be paid out upon unstaking"
        );

        // If rewards were accumulated, ensure the user received the reward amount
        finalUserBalance = stakingToken.balanceOf(user);
        uint256 expectedUserBalance = INITIAL_USER_BALANCE + userRewards;
        console.log("finalUserBalance", finalUserBalance);

        assertEq(
            finalUserBalance,
            expectedUserBalance,
            "User balance should include the staked amount and accumulated rewards"
        );
    }

    function testUnstakeExceedsDailyLimitFails() public {
    // Stake and request unstake
    stakeTokens(STAKE_AMOUNT);

    stakingContract.setDailyWithdrawalThreshold(100000* 10 ** 18);

    vm.startPrank(user);
    stakingContract.requestUnstake(1);

    // Simulate passage of time past unstaking delay
    vm.warp(block.timestamp + 4 days);



    // Attempt to unstake, should fail due to limit
    vm.expectRevert(DailyWithdrawalLimitExceeded.selector);
    stakingContract.unstake(1, STAKE_AMOUNT);

 
     vm.stopPrank();
}

}
