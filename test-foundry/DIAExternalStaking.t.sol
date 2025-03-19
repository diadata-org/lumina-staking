// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../contracts/DIAExternalStaking.sol";
import "../contracts/DIARewardsDistribution.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

contract DIAExternalStakingTest is Test {
    DIAExternalStaking stakingContract;
    IERC20 stakingToken;
    address owner = address(this);
    address user = address(0x123);

    address rewardsWallet = address(0x124);

    function setUp() public {
        stakingToken = IERC20(address(new MockERC20("TestToken", "TT", 18)));
        stakingContract = new DIAExternalStaking(
            3 days,
            address(stakingToken),
            address(rewardsWallet),
            100
        );

        deal(address(stakingToken), user, 1000 * 10 ** 18);
        deal(address(stakingToken), rewardsWallet, 10000000 * 10 ** 18);

        deal(address(stakingToken), address(stakingContract), 1000 * 10 ** 18);
        vm.startPrank(rewardsWallet);

        stakingToken.approve(address(stakingContract), 10000000 * 10 ** 18);

        // stakingContract.updateRewardsWallet(rewardsWallet);
    }

   function testStake() public {
    vm.startPrank(user);
    
    uint256 initialUserBalance = stakingToken.balanceOf(user);
    uint256 initialContractBalance = stakingToken.balanceOf(address(stakingContract));
    uint256 stakeAmount = 100 * 10 ** 18;

    // Approve the staking contract to transfer tokens on behalf of the user
    stakingToken.approve(address(stakingContract), stakeAmount);

    // Stake tokens
    stakingContract.stake(stakeAmount);
    vm.stopPrank();

    // Check updated balances
    uint256 finalUserBalance = stakingToken.balanceOf(user);
    uint256 finalContractBalance = stakingToken.balanceOf(address(stakingContract));

    // Ensure the contract balance increased and user balance decreased
    assertEq(finalContractBalance, initialContractBalance + stakeAmount, "Contract balance should increase");
    assertEq(finalUserBalance, initialUserBalance - stakeAmount, "User balance should decrease");

    // Verify the staking store
    (address beneficiary, uint256 principal, , , ) = stakingContract.stakingStores(1);
    assertEq(beneficiary, user, "Beneficiary should match the user");
    assertEq(principal, stakeAmount, "Principal should match the staked amount");
}

    function testRequestUnstake() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);
        // vm.stopPrank();

        console.log("requestUns------------take");

        (, , , , uint256 unstakingRequestTime) = stakingContract.stakingStores(
            1
        );
        console.log("unstakingRequestTime", unstakingRequestTime);
        // assertGt(unstakingRequestTime, 0);
    }

    function testUnstake() public {
        console.log(
            "rewards wallet balance",
            stakingToken.balanceOf(rewardsWallet)
        );

        console.log(
            "rewards wallet allowance",
            stakingToken.allowance(rewardsWallet, address(stakingContract))
        );

        console.log("contract address", address(stakingContract));

        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), 100000 * 10 ** 18);

        // stakingToken.transfer(address(stakingContract), 100 * 10 ** 18);

        stakingContract.stake(100 * 10 ** 18);
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        console.log("request u address", address(stakingContract));

        console.log("request st address", address(stakingContract));

        vm.warp(block.timestamp + 4 days);

        vm.startPrank(user);
        console.log("----");
        //  vm.expectRevert(DIAExternalStaking.UnstakingNotRequested.selector);

        console.log(
            "stakingContract wallet balance",
            stakingToken.balanceOf(address(stakingContract))
        );

        console.log(
            "stakingContract wallet allowance",
            stakingToken.allowance(
                address(stakingContract),
                address(stakingContract)
            )
        );

        stakingContract.unstake(1);

        console.log("request unstake address", address(stakingContract));

        vm.stopPrank();

        (, , uint256 reward, , ) = stakingContract.stakingStores(1);
        assertEq(reward, 0);
    }

    function testRewardAccumulation() public {
    vm.startPrank(user);
    stakingToken.approve(address(stakingContract), 100 * 10 ** 18);
    stakingContract.stake(100 * 10 ** 18);
    vm.stopPrank();

    vm.warp(block.timestamp + 5 days); // Simulate time passing

    // uint256 expectedReward = (100 * 10 ** 18 * (rewardRatePerDay ** 5)) / 1e10;
    // uint256 actualReward = stakingContract.getRewardForStakingStore(1);

    // assertApproxEqRel(actualReward, expectedReward, 0.01e18); // Allowing small precision error
}

function testUnstakeBeforePeriodFails() public {
    testStake();
    vm.startPrank(user);
    stakingContract.requestUnstake(1);
    vm.warp(block.timestamp + 2 days); // Not enough time elapsed

    vm.expectRevert(DIAExternalStaking.UnstakingPeriodNotElapsed.selector);
    stakingContract.unstake(1);
}

function testUnstakeWithoutRequestFails() public {
    testStake();
    vm.startPrank(user);
    
    vm.expectRevert(DIAExternalStaking.UnstakingNotRequested.selector);
    stakingContract.unstake(1);
}

function testFullStakeAndUnstake() public {
    testStake();
    vm.startPrank(user);
    stakingContract.requestUnstake(1);
    vm.warp(block.timestamp + 4 days);
    stakingContract.unstake(1);
    vm.stopPrank();

    // Verify user balance
    assertEq(stakingToken.balanceOf(user), 1000 * 10 ** 18); // Should be restored after unstake

    // Verify contract balance
    assertEq(stakingToken.balanceOf(address(stakingContract)), 0); // Contract should be empty
}
}
