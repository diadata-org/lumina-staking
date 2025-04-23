pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../contracts/DIAExternalStaking.sol";
import "../contracts/DIARewardsDistribution.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/DIAWhitelistedStaking.sol";

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
contract DIAStakingTestE2E is Test {
    DIAExternalStaking stakingContracte2e;
    DIAWhitelistedStaking whilelistStaking;

    IERC20 stakingTokene2e;

    address owner = address(this);
    address user = address(0x123);
    address rewardsWallet = address(0x124);

    uint256 constant TOTAL_REWARDS = 500000000000 * 10 * 1e50;
    uint256 constant INITIAL_USER_BALANCE = 1000 * 10 ** 18;
    uint256 constant INITIAL_CONTRACT_BALANCE = 1000 * 10 ** 18;

    uint256 constant STAKING_LIMIT = 1000 * 10 ** 18;

    // Add 500 $DIA to the rewards pool to be paid out over 2 days (250 $DIA/day) with 55% of the rewards flowing for whitelist stakers, 45% for external stakers

    uint256 rewardRatePerDayExternal = (225 * 10 ** 18) / 2; // for Two days
    uint256 rewardRatePerDayWhitelist = (275 * 10 ** 18) / 2;

    // Two delegators
    address delegator1 = address(0xAAA);
    address delegator2 = address(0xBBB);

    // Thress delegators Externale

    address delegator3 = address(0xCCC);
    address delegator4 = address(0xDDD);
    address delegator5 = address(0xEEE);

    address staker3 = address(0x3CC);
    address staker4 = address(0x4DD);
    address staker5 = address(0x5EE);

    address staker6 = address(0x6EE);
    address staker7 = address(0x7EE);
    address staker8 = address(0x8EE);
    address staker9 = address(0x9EE);
    address staker10 = address(0x10EE);

    /*

2 wallets principal

*/

    function setupe2e() public {
        stakingTokene2e = IERC20(address(new MockERC20("TestToken", "TT", 18)));

        // Set unstaking period as 15 minutes

        stakingContracte2e = new DIAExternalStaking(
            15 minutes,
            address(stakingTokene2e),
            rewardsWallet,
            rewardRatePerDayExternal,
            STAKING_LIMIT
        );

        whilelistStaking = new DIAWhitelistedStaking(
            15 minutes,
            address(stakingTokene2e),
            rewardsWallet,
            rewardRatePerDayWhitelist
        );

        stakingContracte2e.setDailyWithdrawalThreshold(10_000);

        deal(address(stakingTokene2e), rewardsWallet, TOTAL_REWARDS);

        vm.startPrank(rewardsWallet);
        stakingTokene2e.approve(address(stakingContracte2e), TOTAL_REWARDS);
        stakingTokene2e.approve(address(whilelistStaking), TOTAL_REWARDS);
    }

    function stakeReq() internal {
        address[10] memory stakers;

        address[11] memory whitelistStakers;

        for (uint256 i = 0; i < whitelistStakers.length; i++) {
            whitelistStakers[i] = address(
                uint160(uint256(keccak256(abi.encodePacked("whitelist", i))))
            );
        }

        uint256 stakeAmount = 50 * 10 ** 18; // 50 tokens per staker

        // Assign unique addresses to stakers
        for (uint256 i = 0; i < 10; i++) {
            stakers[i] = address(uint160(0x100 + i));
            deal(stakers[i], 1 ether); // Give ETH for gas
        }

        // fund deligated wallets 500

        deal(address(stakingTokene2e), delegator2, 500 * 10 ** 18);
        deal(address(stakingTokene2e), delegator1, 500 * 10 ** 18);

        vm.startPrank(delegator1);
        stakingTokene2e.approve(address(stakingContracte2e), 500 * 10 ** 18);
        stakingTokene2e.approve(address(whilelistStaking), 500 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(delegator2);
        stakingTokene2e.approve(address(stakingContracte2e), 500 * 10 ** 18);
        stakingTokene2e.approve(address(whilelistStaking), 500 * 10 ** 18);
        vm.stopPrank();

        // Add 11 whitelist stakers (node operator contracts)

        for (uint256 i = 0; i < 11; i++) {
            vm.startPrank(owner);
            console.log("addWhitelistedStaker", whitelistStakers[i]);
            whilelistStaking.addWhitelistedStaker(whitelistStakers[i]);
            vm.stopPrank();
        }

        // stake from delegater 1 to stakers

        // From two separate addresses delegate 50 $DIA to 10 whitelist stakers (500 $DIA in total)
        //For 8 of the nodes delegate 100%

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(delegator1);
            stakingTokene2e.approve(address(whilelistStaking), stakeAmount);
            console.log("Delegator Share 0");

            console.log(
                "Delegator: %s => Whitelisted: %s index %s",
                delegator1,
                whitelistStakers[i],
                i
            );

            whilelistStaking.stakeForAddress(
                whitelistStakers[i],
                stakeAmount,
                0
            );
            vm.stopPrank();
        }

        //For 3 of the nodes delegate 100%

        for (uint256 i = 5; i < 8; i++) {
            vm.startPrank(delegator2);
            console.log("Delegator Share 0");

            console.log(
                "Delegator: %s => Whitelisted: %s index %s",
                delegator2,
                whitelistStakers[i],
                i
            );

            stakingTokene2e.approve(address(whilelistStaking), stakeAmount);
            whilelistStaking.stakeForAddress(
                whitelistStakers[i],
                stakeAmount,
                0
            );
            vm.stopPrank();
        }

        //For 1 of the nodes delegate 80%

        vm.startPrank(delegator2);
        stakingTokene2e.approve(address(whilelistStaking), stakeAmount);
        console.log("Delegator Share 20");
        console.log(
            "Delegator: %s => Whitelisted: %s index %s",
            delegator2,
            whitelistStakers[8],
            8
        );

        whilelistStaking.stakeForAddress(
            whitelistStakers[8],
            stakeAmount,
            2000
        );
        vm.stopPrank();

        //For 1 of the nodes delegate 50%

        vm.startPrank(delegator2);
        stakingTokene2e.approve(address(whilelistStaking), stakeAmount);
        console.log("Delegator Share 50");
        console.log(
            "Delegator: %s => Whitelisted: %s index %s",
            delegator2,
            whitelistStakers[9],
            9
        );
        whilelistStaking.stakeForAddress(
            whitelistStakers[9],
            stakeAmount,
            5000
        );
        vm.stopPrank();

        deal(address(stakingTokene2e), whitelistStakers[10], 500 * 10 ** 18);

        vm.startPrank(whitelistStakers[10]);
        stakingTokene2e.approve(address(whilelistStaking), stakeAmount);
        console.log("Delegator Share 100");
        console.log(
            "Delegator: %s => Whitelisted: %s index %s",
            whitelistStakers[10],
            whitelistStakers[10],
            10
        );

        whilelistStaking.stake(stakeAmount);
        vm.stopPrank();

        for (uint256 i = 0; i < 11; i++) {
            uint256[] memory index = whilelistStaking
                .getStakingIndicesByBeneficiary(whitelistStakers[i]);
            console.log("index", index[0]);
        }

        // Create a pool with 1 000 $DIA stake cap for external stakers

        deal(address(stakingTokene2e), delegator3, 500 * 10 ** 18);
        deal(address(stakingTokene2e), delegator4, 500 * 10 ** 18);
        deal(address(stakingTokene2e), delegator5, 500 * 10 ** 18);

        deal(address(stakingTokene2e), staker3, 100 * 10 ** 18);
        deal(address(stakingTokene2e), staker4, 150 * 10 ** 18);
        deal(address(stakingTokene2e), staker5, 200 * 10 ** 18);

        deal(address(stakingTokene2e), staker6, 50 * 10 ** 18);
        deal(address(stakingTokene2e), staker7, 70 * 10 ** 18);
        deal(address(stakingTokene2e), staker8, 89.5 * 10 ** 18);
        deal(address(stakingTokene2e), staker9, 111.11 * 10 ** 18);
        deal(address(stakingTokene2e), staker10, 229.4 * 10 ** 18);

        // stake external 

        stakeExternalHelper(delegator3,staker3,100 * 10 ** 18, 0);
        stakeExternalHelper(delegator4,staker4,150 * 10 ** 18,9000);
        stakeExternalHelper(delegator4,staker5,200 * 10 ** 18,4000);

        stakeExternalIndividual(staker6, 50 * 10 ** 18);
        stakeExternalIndividual(staker7, 70 * 10 ** 18);
        stakeExternalIndividual(staker8, 89.5 * 10 ** 18);
        stakeExternalIndividual(staker9, 111 * 10 ** 18);
        stakeExternalIndividual(staker10, 229.4 * 10 ** 18);

        printTotalStaked();
 




    }

    function printTotalStaked()public {
        uint256 tokenStaked = stakingContracte2e.tokensStaked();
        console.log("Total staked: ",tokenStaked);

        uint256 stakingLimit = stakingContracte2e.stakingLimit();
        console.log("Total Limit: ",stakingLimit);

    }

    

    function stakeExternalHelper(address delegator, address staker,  uint256 stakeAmount, uint32 principalShareBps) public{
        printTotalStaked();
        vm.startPrank(delegator);
        stakingTokene2e.approve(address(stakingContracte2e), stakeAmount);
         console.log(
            "Delegator: %s => External: %s principalShareBps %s",
            delegator,
            staker,
            principalShareBps
        );

        stakingContracte2e.stakeForAddress(staker, stakeAmount, principalShareBps);
        vm.stopPrank();
    }

        function stakeExternalIndividual( address staker,  uint256 stakeAmount) public{
      printTotalStaked();
        vm.startPrank(staker);
        stakingTokene2e.approve(address(stakingContracte2e), stakeAmount);
         console.log(
            "staker: %s => External:  stakeAmount %s",
            staker,
            stakeAmount
        );

        stakingContracte2e.stake(stakeAmount,10000);
        vm.stopPrank();
    }

    function testEndToEndStakingWithRewards() public {
        setupe2e();
        stakeReq();

       
    }
}
