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
        uint256 lastRewardPeriodTime; // Last time rewards period ended
        address[] stakers;  // Array to track all stakers in this plan
    }
    
    struct UserStake {
        uint256 amount;
        uint256 startTime;
        uint256 planId;
        bool isActive;
        uint256 pendingRewards;
    }
    
    mapping(uint256 => StakingPlan) public stakingPlans;
    mapping(address => UserStake) public userStakes;
    
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
        
        // Initialize staking plans
        stakingPlans[1] = StakingPlan(30 days, MONTH_1_RATE, 0, block.timestamp, new address[](0));
        stakingPlans[3] = StakingPlan(90 days, MONTH_3_RATE, 0, block.timestamp, new address[](0));
        stakingPlans[6] = StakingPlan(180 days, MONTH_6_RATE, 0, block.timestamp, new address[](0));
        stakingPlans[12] = StakingPlan(360 days, MONTH_12_RATE, 0, block.timestamp, new address[](0));
    }

    // Helper function to add staker to plan
    function addStakerToPlan(uint256 planId, address staker) internal {
        StakingPlan storage plan = stakingPlans[planId];
        for (uint i = 0; i < plan.stakers.length; i++) {
            if (plan.stakers[i] == staker) return;
        }
        plan.stakers.push(staker);
    }

    // Helper function to remove staker from plan
    function removeStakerFromPlan(uint256 planId, address staker) internal {
        StakingPlan storage plan = stakingPlans[planId];
        for (uint i = 0; i < plan.stakers.length; i++) {
            if (plan.stakers[i] == staker) {
                plan.stakers[i] = plan.stakers[plan.stakers.length - 1];
                plan.stakers.pop();
                break;
            }
        }
    }

    function updatePlanRewards(uint256 planId) internal {
        StakingPlan storage plan = stakingPlans[planId];
        if (plan.totalStaked == 0) {
            plan.lastRewardPeriodTime = block.timestamp;
            return;
        }

        uint256 currentPeriod = (block.timestamp - plan.lastRewardPeriodTime) / plan.durationInSeconds;
        if (currentPeriod > 0) {
            uint256 rewards = plan.durationInSeconds * plan.emissionRate * currentPeriod;
            
            // Update each staker's pending rewards
            for (uint i = 0; i < plan.stakers.length; i++) {
                address staker = plan.stakers[i];
                UserStake storage userStake = userStakes[staker];
                
                if (userStake.isActive) {
                    uint256 userShare = (userStake.amount * 1e18) / plan.totalStaked;
                    uint256 userRewards = (rewards * userShare) / 1e18;
                    userStake.pendingRewards += userRewards;
                }
            }
            
            plan.lastRewardPeriodTime += currentPeriod * plan.durationInSeconds;
        }
    }

    function stake(uint256 amount, uint256 planId) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(stakingPlans[planId].durationInSeconds > 0, "Invalid plan");
        
        updatePlanRewards(planId);
        
        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        UserStake storage userStake = userStakes[msg.sender];
        StakingPlan storage plan = stakingPlans[planId];
        
        if (userStake.isActive) {
            require(userStake.planId == planId, "Cannot stake in different plan");
            userStake.amount += amount;
        } else {
            userStakes[msg.sender] = UserStake({
                amount: amount,
                startTime: block.timestamp,
                planId: planId,
                isActive: true,
                pendingRewards: 0
            });
            addStakerToPlan(planId, msg.sender);
        }
        
        plan.totalStaked += amount;
        
        emit Staked(msg.sender, amount, planId);
    }

    function pendingRewards(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (!userStake.isActive) return 0;
        
        StakingPlan memory plan = stakingPlans[userStake.planId];
        
        uint256 currentPeriod = (block.timestamp - plan.lastRewardPeriodTime) / plan.durationInSeconds;
        uint256 additionalRewards = 0;
        
        if (currentPeriod > 0 && plan.totalStaked > 0) {
            uint256 rewards = plan.durationInSeconds * plan.emissionRate * currentPeriod;
            uint256 userShare = (userStake.amount * 1e18) / plan.totalStaked;
            additionalRewards = (rewards * userShare) / 1e18;
        }
        
        return userStake.pendingRewards + additionalRewards;
    }

    function withdrawRewards() external nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.isActive, "No active stake");
        
        updatePlanRewards(userStake.planId);
        
        uint256 rewards = userStake.pendingRewards;
        require(rewards > 0, "No rewards to withdraw");
        
        userStake.pendingRewards = 0;
        totalWithdrawnRewards += rewards;
        
        stakingToken.transfer(msg.sender, rewards);
        
        emit RewardsWithdrawn(msg.sender, rewards);
    }

    function withdrawStake() external nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.isActive, "No active stake");
        require(
            block.timestamp >= userStake.startTime + stakingPlans[userStake.planId].durationInSeconds,
            "Lock period not expired"
        );
        
        // Update plan rewards
        updatePlanRewards(userStake.planId);
        
        uint256 rewards = userStake.pendingRewards;
        uint256 amount = userStake.amount;
        uint256 planId = userStake.planId;
        
        // Update state
        StakingPlan storage plan = stakingPlans[planId];
        plan.totalStaked -= amount;
        userStake.isActive = false;
        userStake.pendingRewards = 0;
        removeStakerFromPlan(planId, msg.sender);
        
        // Transfer original stake
        stakingToken.transfer(msg.sender, amount);
        
        // Transfer final rewards if any
        if (rewards > 0) {
            totalWithdrawnRewards += rewards;
            stakingToken.transfer(msg.sender, rewards);
        }
        
        emit StakeWithdrawn(msg.sender, amount, rewards);
    }
    
    // View functions
    function getStakingPlan(uint256 planId) external view returns (
        uint256 durationInSeconds,
        uint256 emissionRate,
        uint256 totalStaked,
        uint256 lastRewardPeriodTime,
        uint256 stakerCount
    ) {
        StakingPlan storage plan = stakingPlans[planId];
        return (
            plan.durationInSeconds,
            plan.emissionRate,
            plan.totalStaked,
            plan.lastRewardPeriodTime,
            plan.stakers.length
        );
    }
    
    function getUserStake(address user) external view returns (UserStake memory) {
        return userStakes[user];
    }
}