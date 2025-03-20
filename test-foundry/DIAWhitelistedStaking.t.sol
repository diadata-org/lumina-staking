// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../contracts/DIAWhitelistedStaking.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Test contract for DIAWhitelistedStaking
contract DIAWhitelistedStakingTest is Test {
    DIAWhitelistedStaking stakingContract;
    IERC20 stakingToken;
    address owner = address(this);
    address user = address(0x123);
    address rewardsWallet = address(0x124);

    uint256 constant STAKE_AMOUNT = 100 * 10**18;
    uint256 constant INITIAL_USER_BALANCE = 1000 * 10**18;
    uint256 constant INITIAL_CONTRACT_BALANCE = 1000 * 10**18;

    // Setup function for initializing contracts and balances
    function setUp() public {
        stakingToken = IERC20(address(new MockERC20("TestToken", "TT", 18)));
        stakingContract = new DIAWhitelistedStaking(3 days, address(stakingToken), rewardsWallet, 100);

        deal(address(stakingToken), user, INITIAL_USER_BALANCE);
        deal(address(stakingToken), rewardsWallet, 10000000 * 10**18);
        deal(address(stakingToken), address(stakingContract), INITIAL_CONTRACT_BALANCE);

        vm.startPrank(rewardsWallet);
        stakingToken.approve(address(stakingContract), 10000000 * 10**18);
    }

    // Helper function for staking tokens
    function stakeTokens(uint256 amount) internal {
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), amount);
        stakingContract.stake(amount);
        vm.stopPrank();
    }

    // Test staking functionality
    function testStake() public {
        uint256 initialUserBalance = stakingToken.balanceOf(user);
        uint256 initialContractBalance = stakingToken.balanceOf(address(stakingContract));

        stakeTokens(STAKE_AMOUNT);

        uint256 finalUserBalance = stakingToken.balanceOf(user);
        uint256 finalContractBalance = stakingToken.balanceOf(address(stakingContract));

        // Ensure balances are updated correctly
        assertEq(finalContractBalance, initialContractBalance + STAKE_AMOUNT, "Contract balance should increase");
        assertEq(finalUserBalance, initialUserBalance - STAKE_AMOUNT, "User balance should decrease");

        // Verify staking store
        (address beneficiary, , uint256 principal, , , ,) = stakingContract.stakingStores(1);
        assertEq(beneficiary, user, "Beneficiary should match the user");
        assertEq(principal, STAKE_AMOUNT, "Principal should match the staked amount");
    }

    // Test unstaking request
    function testRequestUnstake() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);
        (, , , , , , uint256 unstakingRequestTime) = stakingContract.stakingStores(1);

        console.log("Unstaking request time", unstakingRequestTime);
        // You may assert unstakingRequestTime here if needed
        // assertGt(unstakingRequestTime, 0, "Unstaking request time should be greater than 0");
    }

    // Test unstaking after the period
    function testUnstake() public {
        stakeTokens(STAKE_AMOUNT);
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Fast-forward time by 4 days
        vm.warp(block.timestamp + 4 days);

        stakingContract.unstake(1);
        vm.stopPrank();

        // Verify reward is zero after unstake (no rewards accumulated in this test)
        (, , , uint256 reward, , ,) = stakingContract.stakingStores(1);
        assertEq(reward, 0, "Reward should be zero after unstaking");
    }

    // Test reward accumulation over time
    function testRewardAccumulation() public {
        stakeTokens(STAKE_AMOUNT);

        // Simulate time passing (5 days)
        vm.warp(block.timestamp + 5 days);

        // Calculate the expected reward and verify (stubbed for now)
        // uint256 expectedReward = ...;
        // uint256 actualReward = stakingContract.getRewardForStakingStore(1);
        // assertApproxEqRel(actualReward, expectedReward, 0.01e18);
    }

    // Test if unstaking fails before the period has elapsed
    function testUnstakeBeforePeriodFails() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Fast-forward time by only 2 days (not enough to unstake)
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(DIAWhitelistedStaking.UnstakingPeriodNotElapsed.selector);
        stakingContract.unstake(1);
    }

    // Test if unstaking without request fails
    function testUnstakeWithoutRequestFails() public {
        testStake();
        vm.startPrank(user);

        // Attempt unstake without requesting
        vm.expectRevert(DIAWhitelistedStaking.UnstakingNotRequested.selector);
        stakingContract.unstake(1);
    }

    // Test full stake and unstake flow
    function testFullStakeAndUnstake() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Fast-forward time by 4 days
        vm.warp(block.timestamp + 4 days);

        stakingContract.unstake(1);
        vm.stopPrank();
    uint256 rewardBeforeUnstake = stakingContract.getRewardForStakingStore(1);

    console.log("INITIAL_USER_BALANCE",INITIAL_USER_BALANCE);
    console.log("rewardBeforeUnstake",rewardBeforeUnstake);


        // Verify user balance is restored after unstake
 
        assertEq(stakingToken.balanceOf(user), INITIAL_USER_BALANCE  + rewardBeforeUnstake, "User balance should be restored after unstake");

    }
}