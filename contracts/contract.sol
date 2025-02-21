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
    }
    
    struct UserStake {
        uint256 amount;
        uint256 startTime;
        uint256 planId;
        bool isActive;
        uint256 lastRewardWithdrawTime;
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
        stakingPlans[1] = StakingPlan(30 days, MONTH_1_RATE, 0);
        stakingPlans[3] = StakingPlan(90 days, MONTH_3_RATE, 0);
        stakingPlans[6] = StakingPlan(180 days, MONTH_6_RATE, 0);
        stakingPlans[12] = StakingPlan(360 days, MONTH_12_RATE, 0);
    }
    
    function stake(uint256 amount, uint256 planId) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(stakingPlans[planId].durationInSeconds > 0, "Invalid plan");
        require(!userStakes[msg.sender].isActive, "Already staking");
        
        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        userStakes[msg.sender] = UserStake({
            amount: amount,
            startTime: block.timestamp,
            planId: planId,
            isActive: true,
            lastRewardWithdrawTime: 0
        });
        
        stakingPlans[planId].totalStaked += amount;
        
        emit Staked(msg.sender, amount, planId);
    }
    
    function calculateRewards(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (!userStake.isActive) return 0;
        
        // Check if max rewards limit has been reached
        if (totalWithdrawnRewards >= MAX_REWARDS) return 0;
        
        StakingPlan memory plan = stakingPlans[userStake.planId];
        
        // Calculate time since last reward claim (or start time if never claimed)
        uint256 startTime = userStake.lastRewardWithdrawTime > 0 ? 
            userStake.lastRewardWithdrawTime : userStake.startTime;
            
        // Simply calculate time staked since last reward claim
        uint256 timeStaked = block.timestamp - startTime;
        
        // Calculate rewards at the original plan's emission rate
        uint256 userShare = (userStake.amount * 1e18) / plan.totalStaked;
        uint256 calculatedRewards = (timeStaked * plan.emissionRate * userShare) / 1e18;
        
        // Ensure we don't exceed the max rewards limit
        if (totalWithdrawnRewards + calculatedRewards > MAX_REWARDS) {
            calculatedRewards = MAX_REWARDS - totalWithdrawnRewards;
        }
        
        return calculatedRewards;
    }
    
    function withdrawRewards() external nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.isActive, "No active stake");
        
        uint256 rewards = calculateRewards(msg.sender);
        require(rewards > 0, "No rewards to withdraw");
        
        // Update the last reward withdrawal time
        userStake.lastRewardWithdrawTime = block.timestamp;
        
        // Update total withdrawn rewards
        totalWithdrawnRewards += rewards;
        
        // Transfer rewards
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
        
        // Get final rewards before withdrawing stake
        uint256 rewards = calculateRewards(msg.sender);
        uint256 amount = userStake.amount;
        
        // Update state
        stakingPlans[userStake.planId].totalStaked -= amount;
        userStake.isActive = false;
        
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
    function getStakingPlan(uint256 planId) external view returns (StakingPlan memory) {
        return stakingPlans[planId];
    }
    
    function getUserStake(address user) external view returns (UserStake memory) {
        return userStakes[user];
    }
}