// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/DIAExternalStaking.sol";
import "../contracts/StakingErrorsAndEvents.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 10000000000000000 * 10 ** 18);
    }
}

contract DIAExternalStakingTest is Test {
    DIAExternalStaking public staking;
    MockToken public token;
    address public rewardsWallet;
    address public admin;
    address public user1;
    address public random;

    address public user2;
    address public user3;
    uint256 public constant STAKING_LIMIT = 1000000 * 10 ** 18;
    uint256 public constant UNSTAKING_DURATION = 7 days;

    function setUp() public {
        admin = address(0x4);
        vm.startPrank(admin);
        token = new MockToken();
        rewardsWallet = address(0x123);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        random = address(0x10);

        staking = new DIAExternalStaking(
            UNSTAKING_DURATION,
            address(token),
            STAKING_LIMIT
        );

        // Transfer tokens to test users
        token.transfer(user1, 100010 * 10 ** 18);
        token.transfer(user2, 100000 * 10 ** 18);
        token.transfer(user3, 100000 * 10 ** 18);
        token.transfer(rewardsWallet, 10000000000 * 10 ** 18);
        staking.setWithdrawalCapBps(1000);
        vm.stopPrank();
        vm.prank(rewardsWallet);
        token.approve(address(staking), 10000000000 * 10 ** 18);
    }

    function test_InitialState() public {
        assertEq(address(staking.STAKING_TOKEN()), address(token));
        assertEq(staking.unstakingDuration(), UNSTAKING_DURATION);
        assertEq(staking.stakingLimit(), STAKING_LIMIT);
        assertEq(staking.tokensStaked(), 0);
        assertEq(staking.totalPoolSize(), 0);
        assertEq(staking.totalShareAmount(), 0);
    }

    function test_Stake() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000; // 10%

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        vm.stopPrank();

        assertEq(staking.tokensStaked(), amount);
        assertEq(staking.totalPoolSize(), amount);
        assertEq(staking.totalShareAmount(), amount);

        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 poolShares,
            uint64 stakingStartTime,
            uint64 unstakingRequestTime,
            uint32 principalWalletShareBps
        ) = staking.stakingStores(1);

        assertEq(beneficiary, user1);
        assertEq(principalPayoutWallet, user1);
        assertEq(principal, amount);
        assertEq(principalWalletShareBps, principalShareBps);
    }

    function test_StakeForAddress() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000; // 10%

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stakeForAddress(user2, amount, principalShareBps);
        vm.stopPrank();

        (
            address beneficiary,
            address principalPayoutWallet, // principalUnstaker
            // principal
            // poolShares
            // stakingStartTime
            // unstakingRequestTime
            // principalWalletShareBps
            // pendingPrincipalWalletShareBps
            ,
            ,
            ,
            ,
            ,


        ) = // pendingShareUpdateTime
            staking.stakingStores(1);

        assertEq(beneficiary, user2);
        assertEq(principalPayoutWallet, user1);
    }

    function test_RequestUnstake() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        staking.requestUnstake(1);
        vm.stopPrank();

        (
            ,
            ,
            ,
            ,
            ,
            ,
            // beneficiary
            // principalPayoutWallet
            // principalUnstaker
            // principal
            // poolShares
            // stakingStartTime
            uint64 unstakingRequestTime, // principalWalletShareBps


        ) = // pendingShareUpdateTime
            staking.stakingStores(1);

        assertEq(unstakingRequestTime, uint64(block.timestamp));
    }

     function test_AlreadyRequestedUnstake() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        staking.requestUnstake(1);
        vm.expectRevert(AlreadyRequestedUnstake.selector);
        staking.requestUnstake(1);

        vm.stopPrank();

        (
            ,
            ,
            ,
            ,
            ,
            ,
            // beneficiary
            // principalPayoutWallet
            // principalUnstaker
            // principal
            // poolShares
            // stakingStartTime
            uint64 unstakingRequestTime, // principalWalletShareBps


        ) = // pendingShareUpdateTime
            staking.stakingStores(1);

        assertEq(unstakingRequestTime, uint64(block.timestamp));
    }

    function test_RequestUnstake_InvalidAccount() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        vm.stopPrank();

        vm.prank(random);
        vm.expectRevert(AccessDenied.selector);
        staking.requestUnstake(1);
    }

    function test_CompleteUnstake() public {
        uint256 amount = 1000000 * 10 ** 18;
        uint32 principalShareBps = 8000;

        vm.startPrank(user1);
 
                deal(address(token), user1, amount);

        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        staking.requestUnstake(1);
        vm.stopPrank();

        // Add rewards round 1
        vm.startPrank(rewardsWallet);
        token.transfer(address(staking), 300000);
        staking.addRewardToPool(100000);
        vm.stopPrank();

        // Fast forward time
        vm.warp(block.timestamp + UNSTAKING_DURATION + 1);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        // Amount reduced for daily withdrawal limit
        staking.unstake(1, 1000);
        uint256 balanceAfter = token.balanceOf(user1);

        assertGt(balanceAfter, balanceBefore);

        // Add rewards round 2
        vm.startPrank(rewardsWallet);
        staking.addRewardToPool(100000);
        vm.stopPrank();

        vm.startPrank(user1);
        staking.requestUnstake(1);
				vm.stopPrank();

        // Fast forward time
        vm.warp(block.timestamp + UNSTAKING_DURATION + 3);

        balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        // Amount reduced for daily withdrawal limit
        staking.unstake(1, 200);
        balanceAfter = token.balanceOf(user1);
    }

    function test_ExactUnstake() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 10000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        staking.requestUnstake(1);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(rewardsWallet);
        token.transfer(address(staking), 100 * 10 ** 18);
        staking.addRewardToPool(100 * 10 ** 18);
        vm.stopPrank();

        // Fast forward time
        vm.warp(block.timestamp + UNSTAKING_DURATION + 1);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        // Amount reduced for daily withdrawal limit
        staking.unstake(1, 100 * 10 ** 18);
        uint256 balanceAfter = token.balanceOf(user1);

        assertGt(balanceAfter, balanceBefore);
    }

    function test_UpdatePrincipalPayoutWallet() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        staking.updatePrincipalPayoutWallet(user2, 1);
        vm.stopPrank();

        (
            ,
            // beneficiary
            address principalPayoutWallet, // principalUnstaker
            // principal
            // poolShares
            // stakingStartTime
            // unstakingRequestTime
            // principalWalletShareBps
            // pendingPrincipalWalletShareBps
            ,
            ,
            ,
            ,
            ,

        ) = // pendingShareUpdateTime
            staking.stakingStores(1);

        assertEq(principalPayoutWallet, user2);
    }

     function test_UpdatePrincipalPayoutWallet_NotPrincipalUnstaker() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
                vm.stopPrank();
        vm.startPrank(user2);
vm.expectRevert(NotPrincipalUnstaker.selector);
        staking.updatePrincipalPayoutWallet(user2, 1);
 
    }

    function stakeTokens(uint256 amount) internal {
        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, 0);
        vm.stopPrank();
    }

    // function test_UnstakeExceedsDailyLimitFails() public {
    //     // Stake and request unstake
    //     uint256 STAKE_AMOUNT = 100 * 10 ** 18;

    //     stakeTokens(STAKE_AMOUNT);

    //     vm.startPrank(admin);

    //     staking.setDailyWithdrawalThreshold(100000 * 10 ** 18);

    //     vm.startPrank(user1);
    //     staking.requestUnstake(1);

    //     // Simulate passage of time past unstaking delay
    //     vm.warp(block.timestamp + 4 days);

    //     // Attempt to unstake, should fail due to limit
    //     vm.expectRevert(DailyWithdrawalLimitExceeded.selector);
    //     staking.unstake(1, STAKE_AMOUNT);

    //     vm.stopPrank();
    // }

    function testSetInvalidDailyWithdrawalThreshold() public {
        uint256 newThreshold = 0;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidDailyWithdrawalThreshold.selector,
                newThreshold
            )
        );

        staking.setDailyWithdrawalThreshold(newThreshold);
    }

    function testSetDailyWithdrawalThresholdEmitsEvent() public {
        uint256 oldThreshold = staking.dailyWithdrawalThreshold();
        uint256 newThreshold = oldThreshold + 1000;

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit DailyWithdrawalThresholdUpdated(oldThreshold, newThreshold);

        staking.setDailyWithdrawalThreshold(newThreshold);
    }

    function testGetStakingIndicesByBeneficiary() public {

           vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);


        uint256[] memory indices = staking.getStakingIndicesByBeneficiary(
            address(user1)
        );
        assertEq(indices.length, 1);
     }

    function testGetStakingIndicesByPrincipalUnstaker() public {

           vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);

        uint256[] memory indices = staking.getStakingIndicesByPrincipalUnstaker(
            user1
        );
        assertEq(indices.length, 1);
    }

    function testGetStakingIndicesByPayoutWallet() public {

           vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);

        uint256[] memory indices = staking.getStakingIndicesByPayoutWallet(
            user1
        );
        assertEq(indices.length, 1);
     }

    function test_RevertWhen_StakeBelowMinimum() public {
        uint256 amount = 10 * 10 ** 18; // Below minimum stake
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(1 * 10 ** 18, principalShareBps);
        staking.stake(1 * 10 ** 18, principalShareBps);

        vm.expectRevert(
            abi.encodeWithSelector(
                AmountBelowMinimumStake.selector,
                0.5 * 10 ** 18
            )
        );
        staking.stake(0.5 * 10 ** 18, principalShareBps);
        vm.stopPrank();
    }

    function test_RevertWhen_StakeAboveLimit() public {
        uint256 amount = STAKING_LIMIT + 1;
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        vm.expectRevert(
            abi.encodeWithSelector(AmountAboveStakingLimit.selector, amount)
        );
        staking.stake(amount, principalShareBps);
        vm.stopPrank();
    }

    function test_setUnstakingDuration() public {
        uint256 amount = 100001 * 10 ** 18;
        uint32 principalShareBps = 1000;

        vm.prank(admin);
        staking.setUnstakingDuration(19 days);

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);

        staking.requestUnstake(1);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(rewardsWallet);
        token.transfer(address(staking), 100 * 10 ** 18);
        staking.addRewardToPool(100 * 10 ** 18);
        vm.stopPrank();

        // Fast forward time
        vm.warp(block.timestamp + UNSTAKING_DURATION + 1);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(UnstakingPeriodNotElapsed.selector)
        );
        staking.unstake(1, 100 * 10 ** 18);
        vm.prank(admin);
        staking.setUnstakingDuration(1 days);
    }

    function test_UnstakingDurationTooShort() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(UnstakingDurationTooShort.selector)
        );
        staking.setUnstakingDuration(12 hours);
    }

    function test_UnstakingDurationTooLong() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(UnstakingDurationTooLong.selector)
        );
        staking.setUnstakingDuration(21 days);
    }

    function test_InvalidWithdrawalCap() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidWithdrawalCap.selector, 10001)
        );
        staking.setWithdrawalCapBps(10001);
    }

    //     function test_RevertWhen_UnstakeAboveThreshold() public {
    //     uint256 amount = 10000 * 10e18;
    //     uint32 principalShareBps = 1000;

    //     vm.startPrank(user1);
    //     token.approve(address(staking), amount);
    //     vm.expectRevert(abi.encodeWithSelector(AmountAboveStakingLimit.selector, amount));
    //     staking.stake(amount, principalShareBps);
    //     vm.stopPrank();
    // }

    function test_RevertWhen_InvalidPrincipalShare() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 10001; // Above 100%

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        vm.expectRevert(InvalidPrincipalWalletShare.selector);
        staking.stake(amount, principalShareBps);
        vm.stopPrank();
    }

    function test_RevertWhen_UnstakeBeforeDuration() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        staking.requestUnstake(1);
        vm.stopPrank();

        vm.warp(block.timestamp + UNSTAKING_DURATION - 1);

        vm.prank(user1);
        vm.expectRevert(UnstakingPeriodNotElapsed.selector);
        staking.unstake(1, 10);
    }

     function test_Unstake_UnstakingNotRequested() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
         vm.stopPrank();

        vm.warp(block.timestamp + UNSTAKING_DURATION - 1);

        vm.prank(user1);
        vm.expectRevert(UnstakingNotRequested.selector);
        staking.unstake(1, 10);
    }

    //  function test_Unstake_AmountExceedsStaked() public {
    //     uint256 amount = 1000 * 10 ** 18;
    //     uint32 principalShareBps = 1000;

    //     vm.startPrank(user1);
    //     token.approve(address(staking), amount);
    //     staking.stake(amount, principalShareBps);
    //     staking.requestUnstake(1);
    //      vm.stopPrank();

    //     vm.warp(block.timestamp + UNSTAKING_DURATION - 1);

    //     vm.prank(user1);
    //     vm.expectRevert(DailyWithdrawalLimitExceeded.selector);
    //     staking.unstake(1, amount+1);
    // }



     function test_GetRewardForStakingStore() public {

        vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);

        staking.getRewardForStakingStore(1);
       
    }

        function test_requestPrincipalWalletShareUpdate() public {

        vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);

        staking.requestPrincipalWalletShareUpdate(1,100);
       
    }

      function test_requestPrincipalWalletShareUpdate_NotBeneficiary() public {

        vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);
        vm.startPrank(user2);
        vm.expectRevert(NotBeneficiary.selector);
        staking.requestPrincipalWalletShareUpdate(1,100);
       
    }

      function test_requestPrincipalWalletShareUpdate_InvalidPrincipalWalletShare() public {

        vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);
        vm.startPrank(user1);
        vm.expectRevert(InvalidPrincipalWalletShare.selector);
        staking.requestPrincipalWalletShareUpdate(1,10001);
       
    }

    function test_updatePrincipalUnstaker() public {

        vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);
        vm.startPrank(user1);
         staking.updatePrincipalUnstaker(user2,1);
       
    }

     function test_updatePrincipalUnstaker_ZeroAddress() public {

        vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);
        vm.startPrank(user1);
         vm.expectRevert(ZeroAddress.selector);
         staking.updatePrincipalUnstaker(address(0x000),1);
       
    }

     function test_updatePrincipalUnstaker_NotPrincipalUnstaker() public {

        vm.startPrank(user1);
        token.approve(address(staking), 1 * 10 ** 18);
        staking.stake(1 * 10 ** 18, 1);
        vm.startPrank(user2);
         vm.expectRevert(NotPrincipalUnstaker.selector);
         staking.updatePrincipalUnstaker(address(0x001),1);
       
    }

    function test_PrincipalShareUpdateAtGracePeriod() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 1000;
        uint32 newShareBps = 2000;

        vm.startPrank(user1);
        token.approve(address(staking), amount);
        staking.stake(amount, principalShareBps);
        staking.requestPrincipalWalletShareUpdate(1, newShareBps);
        vm.stopPrank();

        // Check initial share before grace period
        assertEq(staking.getCurrentPrincipalWalletShareBps(1), principalShareBps, "Share should not change before grace period");

        // Fast forward to just before grace period
        vm.warp(block.timestamp + staking.SHARE_UPDATE_GRACE_PERIOD() - 1);
        assertEq(staking.getCurrentPrincipalWalletShareBps(1), principalShareBps, "Share should not change before grace period ends");

        // Fast forward past grace period
        vm.warp(block.timestamp + 2);
        assertEq(staking.getCurrentPrincipalWalletShareBps(1), newShareBps, "Share should update after grace period");
    }
}
