// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenStaking is ReentrancyGuard {
    IERC20 public stakingToken;
    address public vestingContract;
    
    struct StakingPlan {
        uint256 durationInSeconds;
        uint256 emissionRate; // Tokens per second (in wei)
        uint256 totalStaked;  // Total tokens staked in this plan
        uint256 lastUpdateTime; // Last time rewards were calculated
        uint256 rewardPerTokenStored; // Accumulated rewards per token
        uint256 startTime;    // Time when first stake was made in this plan
        bool isActive;        // Whether the plan has any stakers
    }

    struct UserStake {
        uint256 amount;
        bool isActive;
        uint256 rewards; // Accumulated rewards
        uint256 userRewardPerTokenPaid; // Last rewards per token paid to user
    }
    
    mapping(uint256 => StakingPlan) public stakingPlans;
    mapping(address => mapping(uint256 => UserStake)) public userStakes;
    
    uint256 public constant MAX_REWARDS = 100_000_000 * 1e18; // 100M tokens in wei
    uint256 public totalWithdrawnRewards;
    
    // Constants for emission rates (in wei)
    uint256 constant MONTH_1_RATE = 53000000000000000; // 0.053 SAGNT/second
    uint256 constant MONTH_3_RATE = 127200000000000000; // 0.1272 SAGNT/second
    uint256 constant MONTH_6_RATE = 275800000000000000; // 0.2758 SAGNT/second
    uint256 constant MONTH_12_RATE = 604200000000000000; // 0.6042 SAGNT/second
    
    // Events
    event Staked(address indexed user, uint256 amount, uint256 planId);
    event RewardsWithdrawn(address indexed user, uint256 amount);
    event StakeWithdrawn(address indexed user, uint256 stakeAmount, uint256 rewardAmount);
    
    constructor(address _stakingToken, address _vestingContract) {
        stakingToken = IERC20(_stakingToken);
        vestingContract = _vestingContract;
        
        uint256 currentTime = block.timestamp;
        // Initialize staking plans
        stakingPlans[1] = StakingPlan(30 days, MONTH_1_RATE, 0, currentTime, 0, currentTime, false);
        stakingPlans[3] = StakingPlan(90 days, MONTH_3_RATE, 0, currentTime, 0, currentTime, false);
        stakingPlans[6] = StakingPlan(180 days, MONTH_6_RATE, 0, currentTime, 0, currentTime, false);
        stakingPlans[12] = StakingPlan(360 days, MONTH_12_RATE, 0, currentTime, 0, currentTime, false);
    }

    /**
     * @dev Calculate the current reward per token for a plan 
     * @param planId The plan ID
     * @return Current reward per token value
     */
    function rewardPerToken(uint256 planId) public view returns (uint256) {
        StakingPlan memory plan = stakingPlans[planId];
        
        if (plan.totalStaked == 0) {
            return plan.rewardPerTokenStored;
        }
        
        return plan.rewardPerTokenStored + 
            (((block.timestamp - plan.lastUpdateTime) * plan.emissionRate * 1e18) / plan.totalStaked);
    }

    /**
     * @dev Calculate pending rewards for a user
     * @param user Address of the user
     * @param planId The plan ID to query rewards for
     * @return Pending rewards amount
     */
    function pendingRewards(address user, uint256 planId) public view returns (uint256) {
        UserStake memory userStake = userStakes[user][planId];
        
        if (!userStake.isActive) {
            return 0;
        }
        
        StakingPlan memory plan = stakingPlans[planId];
        
        // Check if lock period has completed for the plan
        if (block.timestamp < plan.startTime + plan.durationInSeconds) {
            return 0;
        }
        
        // Get current reward per token for the plan
        uint256 currentRewardPerToken = rewardPerToken(planId);
        
        // Calculate new rewards since last update
        return userStake.rewards + 
               ((userStake.amount * (currentRewardPerToken - userStake.userRewardPerTokenPaid)) / 1e18);
    }

    /**
     * @dev Update reward variables for a plan
     * @param planId The plan ID to update
     */
    function updateRewardVariables(uint256 planId) internal {
        StakingPlan storage plan = stakingPlans[planId];
        
        if (plan.totalStaked == 0) {
            plan.lastUpdateTime = block.timestamp;
            return;
        }
        
        plan.rewardPerTokenStored = rewardPerToken(planId);
        plan.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Update rewards for a specific user
     * @param user Address of the user
     * @param planId The plan ID to update rewards for
     */
    function updateReward(address user, uint256 planId) internal {
        if (user == address(0)) return;
        
        UserStake storage userStake = userStakes[user][planId];
        if (!userStake.isActive) return;
        
        StakingPlan storage plan = stakingPlans[planId];
        
        updateRewardVariables(planId);
        
        // Only calculate earned rewards if lock period has ended for the plan
        if (block.timestamp > plan.startTime + plan.durationInSeconds) {
            // Calculate earned rewards based on accumulated reward per token
            uint256 earnedRewards = (userStake.amount * 
                                   (plan.rewardPerTokenStored - userStake.userRewardPerTokenPaid)) / 1e18;
            
            userStake.rewards += earnedRewards;
        }
        
        userStake.userRewardPerTokenPaid = plan.rewardPerTokenStored;
    }

    /**
     * @dev Stake tokens into the contract
     * @param amount Amount of tokens to stake
     * @param planId Plan ID to stake into
     */
    function stake(uint256 amount, uint256 planId) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(stakingPlans[planId].durationInSeconds > 0, "Invalid plan");
        
        updateReward(msg.sender, planId);
        
        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        UserStake storage userStake = userStakes[msg.sender][planId];
        StakingPlan storage plan = stakingPlans[planId];
        
        // Set plan start time if this is the first stake in this plan
        if (!plan.isActive) {
            plan.startTime = block.timestamp;
            plan.isActive = true;
        }
        
        // Always update reward variables when stake amount changes
        updateRewardVariables(planId);
        
        if (userStake.isActive) {
            userStake.amount += amount;
        } else {
            userStakes[msg.sender][planId] = UserStake({
                amount: amount,
                isActive: true,
                rewards: 0,
                userRewardPerTokenPaid: plan.rewardPerTokenStored
            });
        }
        
        plan.totalStaked += amount;
        
        emit Staked(msg.sender, amount, planId);
    }

    /**
     * @dev Withdraw earned rewards from a specific plan
     * @param planId The plan ID to withdraw rewards from
     */
    function withdrawRewards(uint256 planId) external nonReentrant {
        updateReward(msg.sender, planId);
        
        UserStake storage userStake = userStakes[msg.sender][planId];
        require(userStake.isActive, "No active stake");
        
        uint256 rewards = userStake.rewards;
        require(rewards > 0, "No rewards to withdraw");
        
        userStake.rewards = 0;
        totalWithdrawnRewards += rewards;
        
        require(totalWithdrawnRewards <= MAX_REWARDS, "Maximum rewards limit reached");
        
        stakingToken.transfer(msg.sender, rewards);
        
        emit RewardsWithdrawn(msg.sender, rewards);
    }

    /**
     * @dev Withdraw staked tokens from a specific plan after lock period
     * @param planId The plan ID to withdraw stake from
     */
    function withdrawStake(uint256 planId) external nonReentrant {
        UserStake storage userStake = userStakes[msg.sender][planId];
        require(userStake.isActive, "No active stake");
        
        StakingPlan storage plan = stakingPlans[planId];
        require(
            block.timestamp >= plan.startTime + plan.durationInSeconds,
            "Lock period not expired"
        );
        
        updateReward(msg.sender, planId);
        
        // Update reward variables when total staked amount changes
        updateRewardVariables(planId);
        
        uint256 rewards = userStake.rewards;
        uint256 amount = userStake.amount;
        
        // Update state
        plan.totalStaked -= amount;
        userStake.isActive = false;
        userStake.rewards = 0;
        userStake.amount = 0;
        
        // If this was the last staker in the plan, reset the plan activity
        if (plan.totalStaked == 0) {
            plan.isActive = false;
        }
        
        // Transfer original stake
        stakingToken.transfer(msg.sender, amount);
        
        // Transfer final rewards if any
        if (rewards > 0) {
            totalWithdrawnRewards += rewards;
            require(totalWithdrawnRewards <= MAX_REWARDS, "Maximum rewards limit reached");
            stakingToken.transfer(msg.sender, rewards);
        }
        
        emit StakeWithdrawn(msg.sender, amount, rewards);
    }
    
    /**
     * @dev Get staking plan details
     * @param planId The plan ID to query
     */
    function getStakingPlan(uint256 planId) external view returns (
    uint256 durationInSeconds,
    uint256 emissionRate,
    uint256 totalStaked,
    uint256 lastUpdateTime,
    uint256 rewardPerToken,
    uint256 startTime,
    bool isActive
) {
    StakingPlan storage plan = stakingPlans[planId];
    return (
        plan.durationInSeconds,
        plan.emissionRate,
        plan.totalStaked,
        plan.lastUpdateTime,
        plan.rewardPerTokenStored,
        plan.startTime,
        plan.isActive
    );
}
    
    /**
     * @dev Get user stake details for a specific plan
     * @param user Address of the user
     * @param planId The plan ID to query
     */
    function getUserStake(address user, uint256 planId) external view returns (
        uint256 amount,
        uint256 rewards,
        bool isActive,
        uint256 pendingReward
    ) {
        UserStake memory userStake = userStakes[user][planId];
        return (
            userStake.amount,
            userStake.rewards,
            userStake.isActive,
            pendingRewards(user, planId)
        );
    }

    /**
     * @dev Get total staked amount across all plans for a user
     * @param user Address of the user
     */
    function getTotalUserStake(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256[] memory planIds = new uint256[](4);
        planIds[0] = 1;
        planIds[1] = 3;
        planIds[2] = 6;
        planIds[3] = 12;
        
        for (uint256 i = 0; i < planIds.length; i++) {
            if (userStakes[user][planIds[i]].isActive) {
                total += userStakes[user][planIds[i]].amount;
            }
        }
        
        return total;
    }

    /**
     * @dev Get total pending rewards across all plans for a user
     * @param user Address of the user
     */
    function getTotalPendingRewards(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256[] memory planIds = new uint256[](4);
        planIds[0] = 1;
        planIds[1] = 3;
        planIds[2] = 6;
        planIds[3] = 12;
        
        for (uint256 i = 0; i < planIds.length; i++) {
            total += pendingRewards(user, planIds[i]);
        }
        
        return total;
    }
}