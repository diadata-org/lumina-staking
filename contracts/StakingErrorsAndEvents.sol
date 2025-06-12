pragma solidity 0.8.29;

error AccessDenied();
error AlreadyRequestedUnstake();
error UnstakingNotRequested();
error UnstakingPeriodNotElapsed();
error UnstakingDurationTooShort();
error UnstakingDurationTooLong();
error AmountBelowMinimumStake(uint256 amount);
error ZeroPoolSharesMinted();
error AmountAboveStakingLimit(uint256 amount);
error AmountExceedsStaked();
error InvalidPrincipalWalletShare();
error ZeroAddress();
error DailyWithdrawalLimitExceeded();
error DailyWithdrawalThresholdExceeded();
error InvalidWithdrawalCap(uint256 newBps);
error InvalidDailyWithdrawalThreshold(uint256 newThreshold);
error NotOwner();
error NotPrincipalUnstaker();
error NotWhitelisted();
error NotBeneficiary();
error InvalidStakesPerBeneficiaryLimit();
error InvalidStakingLimit();
error UnclaimedRewards();
error UnstakeSharesSlippageExceeded();

uint256 constant minimumStake = 1 * 10 ** 18; //   minimum stake of 1 tokens
uint32 constant SECONDS_IN_A_DAY = 24 * 60 * 60;

event WithdrawalCapUpdated(uint256 oldCap, uint256 newCap);

event Staked(
    address indexed beneficiary,
    uint256 indexed stakingStoreIndex,
    uint256 amount
);
event UnstakeRequested(
    address indexed requester,
    uint256 indexed stakingStoreIndex
);

event Unstaked(
    uint256 indexed stakingStoreIndex,
    uint256 principalAmount,
    address principalPayoutWallet
);

event Claimed(
    uint256 indexed stakingStoreIndex,
    uint256 principalAmount,
    uint256 principalWalletReward,
    uint256 beneficiaryReward,
    address principalPayoutWallet,
    address beneficiary
);

event RewardAdded(uint256 amount, address rewardSender);

event PrincipalPayoutWalletUpdated(
    address oldWallet,
    address newWallet,
    uint256 stakingStoreIndex
);
event UnstakingDurationUpdated(uint256 oldDuration, uint256 newDuration);
event DailyWithdrawalThresholdUpdated(
    uint256 oldThreshold,
    uint256 newThreshold
);

event PrincipalWalletShareUpdateRequested(
    uint256 indexed stakeId,
    uint32 newBps,
    uint256 timestamp
);

event PrincipalUnstakerUpdated(
    address oldUnstaker,
    address newUnstaker,
    uint256 stakingStoreIndex
);

error MaxStakesPerBeneficiaryReached();

event StakingLimitUpdated(uint256 oldLimit, uint256 newLimit);

event MaxStakesPerBeneficiaryUpdated(uint256 oldLimit, uint256 newLimit);
