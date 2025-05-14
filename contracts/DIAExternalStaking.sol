// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./DIAExternalRewardsDistribution.sol";
import "./StakingErrorsAndEvents.sol";

import "forge-std/console.sol";

contract DIAExternalStaking is
    Ownable,
    ReentrancyGuard,
    DIAExternalRewardsDistribution
{
    using SafeERC20 for IERC20;

    mapping(address => uint256[]) internal stakingIndicesByBeneficiary;
    mapping(address => uint256[]) internal stakingIndicesByPrincipalUnstaker;
    mapping(address => uint256[]) internal stakingIndicesByPayoutWallet;

    uint256 public stakingIndex;

    struct PendingShareUpdate {
        uint32 newShareBps;
        uint64 requestTime;
    }

    mapping(uint256 => PendingShareUpdate) public pendingShareUpdates;
    uint64 public constant SHARE_UPDATE_GRACE_PERIOD = 1 days;

    /// @notice ERC20 token used for staking.
    IERC20 public immutable STAKING_TOKEN;

    struct ExternalStakingStore {
        address beneficiary;
        address principalPayoutWallet;
        address principalUnstaker;
        uint256 principal;
        uint256 poolShares;
        uint64 stakingStartTime;
        uint64 unstakingRequestTime;
        uint32 principalWalletShareBps;
        uint32 pendingPrincipalWalletShareBps;
        uint64 pendingShareUpdateTime;
    }

    /// @notice Variables for tracking the pool state and share
    uint256 public totalPoolSize;
    uint256 public totalShareAmount;

    uint256 public tokensStaked;

    uint256 public stakingLimit;

    /// @notice How long (in seconds) for unstaking to take place
    uint256 public unstakingDuration;

    uint256 public totalDailyWithdrawals;

    uint256 public lastWithdrawalResetDay;
    uint256 public dailyWithdrawalThreshold = 100000 * 10 ** 18; // Set threshold as needed
    uint256 public withdrawalCapBps = 1000; // 1000 bps = 10%

    /// @notice Mapping of staking index to corresponding staking store.
    mapping(uint256 => ExternalStakingStore) public stakingStores;

    modifier onlyBeneficiaryOrPayoutWallet(uint256 stakingStoreIndex) {
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];



        if (
            msg.sender != currentStore.beneficiary &&
            msg.sender != currentStore.principalPayoutWallet
        ) {
            revert AccessDenied();
        }
        _;
    }

    modifier checkDailyWithdrawalLimit(uint256 amount) {
        if (tokensStaked < dailyWithdrawalThreshold) {
            if (block.timestamp / SECONDS_IN_A_DAY > lastWithdrawalResetDay) {
                totalDailyWithdrawals = 0;
                lastWithdrawalResetDay = block.timestamp / SECONDS_IN_A_DAY;
            }

            uint256 availableDailyLimit = (tokensStaked * withdrawalCapBps) /
                10000; // Calculate based on bps
            if (totalDailyWithdrawals + amount > availableDailyLimit) {
                revert DailyWithdrawalLimitExceeded();
            }
        }

        _;
    }

    constructor(
        uint256 _unstakingDuration,
        address _stakingTokenAddress,
        uint256 _stakingLimit
    ) Ownable(msg.sender) DIAExternalRewardsDistribution(_stakingTokenAddress) {
        if (_stakingTokenAddress == address(0)) revert ZeroAddress();

        unstakingDuration = _unstakingDuration;
        STAKING_TOKEN = IERC20(_stakingTokenAddress);
        stakingLimit = _stakingLimit;
    }

    /**
     * @notice Allows a user to stake tokens directly.
     * @param amount The amount of tokens to stake.
     * @param principalWalletShareBps The share of principal going to the delegator in basis points
     */
    function stake(
        uint256 amount,
        uint32 principalWalletShareBps
    ) public nonReentrant {
        _stake(msg.sender, amount, principalWalletShareBps, msg.sender);
    }

    /**
     * @notice Stakes tokens on behalf of a given address.
     * @param beneficiaryAddress Address receiving the staking rewards.
     * @param amount Amount of tokens to be staked.
     */
    function stakeForAddress(
        address beneficiaryAddress,
        uint256 amount,
        uint32 principalWalletShareBps
    ) public nonReentrant{
        _stake(beneficiaryAddress, amount, principalWalletShareBps, msg.sender);
    }

    /**
     * @notice Internal function to handle staking logic
     * @param beneficiaryAddress Address receiving the staking rewards
     * @param amount Amount of tokens to be staked
     * @param principalWalletShareBps The share of principal going to the delegator in basis points
     * @param staker Address performing the stake operation
     */
    function _stake(
        address beneficiaryAddress,
        uint256 amount,
        uint32 principalWalletShareBps,
        address staker
    ) internal {
        if (amount > (stakingLimit - tokensStaked)) {
            revert AmountAboveStakingLimit(amount);
        }

        if (principalWalletShareBps > 10000)
            revert InvalidPrincipalWalletShare();

        if (amount < minimumStake) {
            revert AmountBelowMinimumStake(amount);
        }

        // Transfer tokens
        STAKING_TOKEN.safeTransferFrom(staker, address(this), amount);

        uint256 poolSharesGiven = 0;
        if (totalShareAmount == 0) {
            poolSharesGiven = amount;
        } else {
            poolSharesGiven = (amount * totalShareAmount) / totalPoolSize;
        }

        totalPoolSize += amount;
        totalShareAmount += poolSharesGiven;

        // Create staking entry
        stakingIndex++;
        ExternalStakingStore storage newStore = stakingStores[stakingIndex];
        newStore.beneficiary = beneficiaryAddress;
        newStore.principalPayoutWallet = staker;
        newStore.principal = amount;
        newStore.poolShares = poolSharesGiven;
        newStore.stakingStartTime = uint64(block.timestamp);
        newStore.principalWalletShareBps = principalWalletShareBps;
        newStore.principalUnstaker = staker;

        // Track stake info
        tokensStaked += amount;
        stakingIndicesByBeneficiary[beneficiaryAddress].push(stakingIndex);
        stakingIndicesByPrincipalUnstaker[staker].push(stakingIndex);
        stakingIndicesByPayoutWallet[staker].push(stakingIndex);

        emit Staked(beneficiaryAddress, stakingIndex, amount);
    }

    /**
     * @notice Updates the duration required before unstaking can be completed.
     * @dev Only callable by the contract owner.
     * @param newDuration The new unstaking duration, in seconds.
     * @custom:revert UnstakingDurationTooShort() if the new duration is less than 1 day.
     * @custom:revert UnstakingDurationTooLong() if the new duration exceeds 20 days.
     */
    function setUnstakingDuration(uint256 newDuration) external onlyOwner {
        if (newDuration < 1 days) {
            revert UnstakingDurationTooShort();
        }

        if (newDuration > 20 days) {
            revert UnstakingDurationTooLong();
        }
        emit UnstakingDurationUpdated(unstakingDuration, newDuration);

        unstakingDuration = newDuration;
    }

    function setWithdrawalCapBps(uint256 newBps) external onlyOwner {
        if (newBps > 10000) {
            revert InvalidWithdrawalCap(newBps);
        }

        uint256 oldCap = withdrawalCapBps;
        withdrawalCapBps = newBps;

        emit WithdrawalCapUpdated(oldCap, newBps); // Emit event with old and new values
    }

    function setDailyWithdrawalThreshold(
        uint256 newThreshold
    ) external onlyOwner {
        if (newThreshold <= 0) {
            revert InvalidDailyWithdrawalThreshold(newThreshold);
        }

        uint256 oldThreshold = dailyWithdrawalThreshold;
        dailyWithdrawalThreshold = newThreshold;

        emit DailyWithdrawalThresholdUpdated(oldThreshold, newThreshold);
    }

    function getStakingIndicesByBeneficiary(
        address beneficiary
    ) external view returns (uint256[] memory) {
        return stakingIndicesByBeneficiary[beneficiary];
    }

    function getStakingIndicesByPrincipalUnstaker(
        address unstaker
    ) external view returns (uint256[] memory) {
        return stakingIndicesByPrincipalUnstaker[unstaker];
    }

    function getStakingIndicesByPayoutWallet(
        address payoutWallet
    ) external view returns (uint256[] memory) {
        return stakingIndicesByPayoutWallet[payoutWallet];
    }

    function _removeStakingIndexFromAddressMapping(
        address user,
        uint256 _stakingIndex,
        mapping(address => uint256[]) storage indexMap
    ) internal {
        uint256[] storage indices = indexMap[user];
        for (uint256 i = 0; i < indices.length; i++) {
            if (indices[i] == _stakingIndex) {
                indices[i] = indices[indices.length - 1];
                indices.pop();
                break;
            }
        }
    }

    /**
     * @notice Updates the principal payout wallet for a given staking index.
     * @dev Only callable by the contract owner.
     * @param newWallet New wallet address for receiving the principal.
     * @param stakingStoreIndex Index of the staking store.
     */
    function updatePrincipalPayoutWallet(
        address newWallet,
        uint256 stakingStoreIndex
    ) external {
        if (newWallet == address(0)) revert ZeroAddress();
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];

        address oldWallet = currentStore.principalPayoutWallet;

        currentStore.principalPayoutWallet = newWallet;

        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }

        _removeStakingIndexFromAddressMapping(
            oldWallet,
            stakingStoreIndex,
            stakingIndicesByPayoutWallet
        );
        stakingIndicesByPayoutWallet[newWallet].push(stakingStoreIndex);

        emit PrincipalPayoutWalletUpdated(
            oldWallet,
            newWallet,
            stakingStoreIndex
        );
    }

    /**
     * @notice Allows the current unstaker to update the unstaker.
     * @param newUnstaker New address allowed to unstake the principal.
     * @param stakingStoreIndex Index of the staking store.
     */
    function updatePrincipalUnstaker(
        address newUnstaker,
        uint256 stakingStoreIndex
    ) external {
        if (newUnstaker == address(0)) revert ZeroAddress();
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];
        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }

        currentStore.principalUnstaker = newUnstaker;
    }

    /**
     * @notice Requests unstaking, starting the waiting period.
     * @dev Can only be called by the beneficiary.
     * @param stakingStoreIndex Index of the staking store.
     */
    function requestUnstake(
        uint256 stakingStoreIndex
    ) external nonReentrant onlyBeneficiaryOrPayoutWallet(stakingStoreIndex) {
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];
        if (currentStore.unstakingRequestTime != 0) {
            revert AlreadyRequestedUnstake();
        }

        currentStore.unstakingRequestTime = uint64(block.timestamp);
        emit UnstakeRequested(msg.sender, stakingStoreIndex);
    }

    /**
     * @notice Completes the unstaking process after the required duration.
     * @param stakingStoreIndex Index of the staking store.
     */
    function unstake(
        uint256 stakingStoreIndex,
        uint256 amount
    )
        external
        nonReentrant
        onlyBeneficiaryOrPayoutWallet(stakingStoreIndex)
        //checkDailyWithdrawalLimit(amount)
				//TODO: Fix the check
    {
			// 	console.log("");
			// 	console.log("=================");
  			// console.log("unstake started...");
			// 	console.log("amount", amount);
			// 	console.log("totalPoolSize", totalPoolSize);
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];
        if (currentStore.unstakingRequestTime == 0) {
            revert UnstakingNotRequested();
        }

        if (
            currentStore.unstakingRequestTime + unstakingDuration >
            block.timestamp
        ) {
            revert UnstakingPeriodNotElapsed();
        }

        // Determine how many staking tokens in the pool belong to the unstaker
        uint256 currentAmountOfPool = (currentStore.poolShares *
            totalPoolSize) / totalShareAmount;

        if (amount > currentAmountOfPool) {
            revert AmountExceedsStaked();
        }

        // Determine how much of the requested unstake amount is principal and how much is reward
        uint256 principalUnstakeAmount = (amount * currentStore.principal) /
            currentAmountOfPool;
        uint256 rewardUnstakeAmount = amount - principalUnstakeAmount;

				// console.log("principalUnstakeAmount", principalUnstakeAmount);

        // Determine how many shares we will deduct for unstaking
        uint256 poolSharesUnstakeAmount = (currentStore.poolShares * amount) /
            currentAmountOfPool;

				// console.log("poolSharesUnstakeAmount", poolSharesUnstakeAmount);
				// console.log("totalShareAmount", totalShareAmount);

        uint256 principalToSend = principalUnstakeAmount;
        uint256 rewardToSend = rewardUnstakeAmount;
        currentStore.principal =
            currentStore.principal -
            principalUnstakeAmount;
        tokensStaked -= principalUnstakeAmount;
        currentStore.poolShares -= poolSharesUnstakeAmount;
        currentStore.unstakingRequestTime = 0;
        currentStore.stakingStartTime = uint64(block.timestamp);

        // Update pool shares tracker
        totalDailyWithdrawals += amount;
        totalPoolSize -= amount;
        totalShareAmount -= poolSharesUnstakeAmount;

        uint256 principalWalletReward = (rewardToSend *
            _getCurrentPrincipalWalletShareBps(stakingStoreIndex)) / 10000;
        uint256 beneficiaryReward = rewardToSend - principalWalletReward;

        if (principalWalletReward > 0) {
            STAKING_TOKEN.safeTransfer(
                currentStore.principalPayoutWallet,
                principalWalletReward
            );
        }

        // Send principal tokens to the payout wallet
        STAKING_TOKEN.safeTransfer(
            currentStore.principalPayoutWallet,
            principalToSend
        );

        // Send reward to the beneficiary
        STAKING_TOKEN.safeTransfer(currentStore.beneficiary, beneficiaryReward);

        emit Unstaked(
            stakingStoreIndex,
            principalToSend,
            principalWalletReward,
            beneficiaryReward,
            currentStore.principalPayoutWallet,
            currentStore.beneficiary
        );

				// console.log("-------");
				// console.log("Payouts");
				// console.log("beneficiaryReward", beneficiaryReward);
				// console.log("principalWalletReward", principalWalletReward);
				// console.log("principalToSend", principalToSend);

				// console.log("-------");
				// console.log("After");
				// console.log("totalShareAmount", totalShareAmount);
				// console.log("totalPoolSize", totalPoolSize);
				// console.log("currentStore.poolShares", currentStore.poolShares);
				// console.log("=================");
    }

    function addRewardToPool(uint256 amount) public {
        // Transfer tokens
        STAKING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);

				// console.log("");
				// console.log("=================");
				// console.log("totalPoolSize before", totalPoolSize);
        totalPoolSize += amount;
        emit RewardAdded(amount, msg.sender);
				// console.log("Rewards added", amount);
				// console.log("totalPoolSize", totalPoolSize);
				// console.log("user1 shares", stakingStores[1].poolShares);
				// console.log("user2 shares", stakingStores[2].poolShares);
				// console.log("=================");
    }

    function _getCurrentPrincipalWalletShareBps(
        uint256 stakeId
    ) internal view returns (uint32) {
        PendingShareUpdate memory pending = pendingShareUpdates[stakeId];

        if (
            pending.requestTime > 0 &&
            block.timestamp >= pending.requestTime + SHARE_UPDATE_GRACE_PERIOD
        ) {
            return pending.newShareBps;
        }

        return stakingStores[stakeId].principalWalletShareBps;
    }

    function getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) public view returns (uint256) {
        ExternalStakingStore storage store = stakingStores[stakingStoreIndex];

        uint256 claimableTokens = (store.poolShares * totalPoolSize) / totalShareAmount;

        return claimableTokens - store.principal;
    }

    function requestPrincipalWalletShareUpdate(
        uint256 stakeId,
        uint32 newShareBps
    ) external {
        if (msg.sender != stakingStores[stakeId].beneficiary) {
            revert NotBeneficiary();
        }

        if (newShareBps > 10000) revert InvalidPrincipalWalletShare();

        pendingShareUpdates[stakeId] = PendingShareUpdate({
            newShareBps: newShareBps,
            requestTime: uint64(block.timestamp)
        });

        emit PrincipalWalletShareUpdateRequested(
            stakeId,
            newShareBps,
            block.timestamp
        );
    }
}
