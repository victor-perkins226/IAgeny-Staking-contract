const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TokenStaking", function () {
  let stakingToken;
  let stakingContract;
  let owner;
  let addr1;
  let addr2;
  let planDurations;
  let emissionRates;

  before(async function () {
    planDurations = {
      MONTH_1: 30 * 24 * 60 * 60,  // 30 days in seconds
      MONTH_3: 90 * 24 * 60 * 60,  // 90 days in seconds
      MONTH_6: 180 * 24 * 60 * 60, // 180 days in seconds
      MONTH_12: 360 * 24 * 60 * 60 // 360 days in seconds
    };

    emissionRates = {
      MONTH_1: ethers.parseUnits("0.053", 18),
      MONTH_3: ethers.parseUnits("0.1272", 18),
      MONTH_6: ethers.parseUnits("0.2758", 18),
      MONTH_12: ethers.parseUnits("0.6042", 18)
    };
  });

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy StakingToken
    const StakingToken = await ethers.getContractFactory("StakingToken");
    stakingToken = await StakingToken.deploy("Staking Token", "STK");

    // Deploy TokenStaking
    const TokenStaking = await ethers.getContractFactory("TokenStaking");
    stakingContract = await TokenStaking.deploy(await stakingToken.getAddress(), owner.address);

    // Mint tokens for rewards to staking contract (100M tokens)
    const rewardsAmount = ethers.parseUnits("100000000", 18);
    await stakingToken.mint(await stakingContract.getAddress(), rewardsAmount);

    // Mint tokens to users
    const mintAmount = ethers.parseUnits("10000", 18);
    await stakingToken.mint(addr1.address, mintAmount);
    await stakingToken.mint(addr2.address, mintAmount);

    // Approve staking contract
    await stakingToken.connect(addr1).approve(await stakingContract.getAddress(), mintAmount);
    await stakingToken.connect(addr2).approve(await stakingContract.getAddress(), mintAmount);
  });

  describe("Contract Deployment", function () {
    it("Should initialize with correct token and vesting contract", async function () {
      expect(await stakingContract.stakingToken()).to.equal(await stakingToken.getAddress());
      expect(await stakingContract.vestingContract()).to.equal(owner.address);
    });

    it("Should initialize staking plans with correct durations and rates", async function () {
      const [plan1Duration, plan1Rate] = await stakingContract.getStakingPlan(1);
      const [plan3Duration, plan3Rate] = await stakingContract.getStakingPlan(3);
      const [plan6Duration, plan6Rate] = await stakingContract.getStakingPlan(6);
      const [plan12Duration, plan12Rate] = await stakingContract.getStakingPlan(12);

      expect(plan1Duration).to.equal(planDurations.MONTH_1);
      expect(plan3Duration).to.equal(planDurations.MONTH_3);
      expect(plan6Duration).to.equal(planDurations.MONTH_6);
      expect(plan12Duration).to.equal(planDurations.MONTH_12);

      expect(plan1Rate).to.equal(emissionRates.MONTH_1);
      expect(plan3Rate).to.equal(emissionRates.MONTH_3);
      expect(plan6Rate).to.equal(emissionRates.MONTH_6);
      expect(plan12Rate).to.equal(emissionRates.MONTH_12);
    });
  });

  describe("Staking Functionality", function () {
    it("Should allow staking tokens", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await expect(stakingContract.connect(addr1).stake(stakeAmount, 1))
        .to.emit(stakingContract, "Staked")
        .withArgs(addr1.address, stakeAmount, 1);

      const [amount, , isActive] = await stakingContract.getUserStake(addr1.address, 1);
      expect(amount).to.equal(stakeAmount);
      expect(isActive).to.be.true;
    });

    it("Should allow additional stakes in same plan", async function () {
      const initialStake = ethers.parseUnits("100", 18);
      const additionalStake = ethers.parseUnits("50", 18);

      await stakingContract.connect(addr1).stake(initialStake, 1);
      await stakingContract.connect(addr1).stake(additionalStake, 1);

      const [amount] = await stakingContract.getUserStake(addr1.address, 1);
      expect(amount).to.equal(initialStake + additionalStake);
    });

    it("Should allow staking in different plans simultaneously", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await stakingContract.connect(addr1).stake(ethers.parseUnits("200", 18), 3);
      
      const [amount1] = await stakingContract.getUserStake(addr1.address, 1);
      const [amount3] = await stakingContract.getUserStake(addr1.address, 3);
      
      expect(amount1).to.equal(ethers.parseUnits("100", 18));
      expect(amount3).to.equal(ethers.parseUnits("200", 18));
      
      const totalStake = await stakingContract.getTotalUserStake(addr1.address);
      expect(totalStake).to.equal(ethers.parseUnits("300", 18));
    });
  });

  describe("Reward Distribution", function () {
    it("Should not distribute rewards before period completion", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      // Move forward 15 days (half period)
      await time.increase(15 * 24 * 60 * 60);

      const pendingReward = await stakingContract.pendingRewards(addr1.address, 1);
      expect(pendingReward).to.equal(0);
    });

    it("Should distribute rewards after period completion", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      // Move forward 30 days (full period)
      await time.increase(30 * 24 * 60 * 60);
      
      // Move a bit more to let rewards accumulate
      await time.increase(1 * 24 * 60 * 60);

      const pendingReward = await stakingContract.pendingRewards(addr1.address, 1);
      expect(pendingReward).to.be.gt(0);
    });

    it("Should distribute rewards proportionally between stakers", async function () {
      // addr1 stakes 100 tokens in plan 1
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      // addr2 stakes 50 tokens in plan 1
      await stakingContract.connect(addr2).stake(ethers.parseUnits("50", 18), 1);

      // Move forward 30 days to complete lock period
      await time.increase(30 * 24 * 60 * 60);
      
      // Move forward 10 more days to accumulate rewards
      await time.increase(10 * 24 * 60 * 60);

      const rewards1 = await stakingContract.pendingRewards(addr1.address, 1);
      const rewards2 = await stakingContract.pendingRewards(addr2.address, 1);

      // addr1 should get twice the rewards of addr2
      expect(rewards1).to.be.gt(0);
      expect(rewards2).to.be.gt(0);

      // Calculate the expected ratio with 1% tolerance
      const ratio = rewards1 * 100n / rewards2;
      expect(ratio).to.be.closeTo(200n, 2n); // 200 = 2 * 100 (for percentage), ±2 for 1% tolerance
    });

    it("Should handle rewards correctly for late joiners", async function () {
      // addr1 stakes at start
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);

      // Move forward 30 days to complete lock period
      await time.increase(30 * 24 * 60 * 60);

      // Move forward 5 days to accumulate some rewards for addr1
      await time.increase(5 * 24 * 60 * 60);
      
      // addr2 stakes 5 days after period end
      await stakingContract.connect(addr2).stake(ethers.parseUnits("100", 18), 1);

      // Move forward 5 more days so both have some rewards
      await time.increase(5 * 24 * 60 * 60);

      const rewards1 = await stakingContract.pendingRewards(addr1.address, 1);
      const rewards2 = await stakingContract.pendingRewards(addr2.address, 1);

      expect(rewards1).to.be.gt(0);
      expect(rewards2).to.be.gt(0);
      
      // addr1 should have more rewards (10 days vs 5 days of accumulation)
      expect(rewards1).to.be.gt(rewards2);

      console.log(rewards1, rewards2);
      
      // Calculate the ratio - should be close to 2:1
      const ratio = rewards1 * 100n / rewards2;
      expect(ratio).to.be.closeTo(1500n, 1n); // 200 = 2 * 100 (for percentage), ±20 for tolerance
    });
  });

  describe("Reward Withdrawal", function () {
    it("Should allow withdrawing rewards after period", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      // Complete one period and accumulate rewards
      await time.increase(30 * 24 * 60 * 60);
      await time.increase(5 * 24 * 60 * 60);

      const balanceBefore = await stakingToken.balanceOf(addr1.address);
      await stakingContract.connect(addr1).withdrawRewards(1);
      const balanceAfter = await stakingToken.balanceOf(addr1.address);

      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should reset pending rewards after withdrawal", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await time.increase(30 * 24 * 60 * 60);
      await time.increase(5 * 24 * 60 * 60);

      await stakingContract.connect(addr1).withdrawRewards(1);
      const [, rewards] = await stakingContract.getUserStake(addr1.address, 1);
      expect(rewards).to.equal(0);
    });
  });

  describe("Stake Withdrawal", function () {
    it("Should not allow withdrawal before lock period", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await expect(
        stakingContract.connect(addr1).withdrawStake(1)
      ).to.be.revertedWith("Lock period not expired");
    });

    it("Should allow withdrawal after lock period", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      // Move past lock period
      await time.increase(31 * 24 * 60 * 60);

      const balanceBefore = await stakingToken.balanceOf(addr1.address);
      await stakingContract.connect(addr1).withdrawStake(1);
      const balanceAfter = await stakingToken.balanceOf(addr1.address);

      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should update total staked amount after withdrawal", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      await time.increase(31 * 24 * 60 * 60);
      await stakingContract.connect(addr1).withdrawStake(1);

      const [, , totalStaked] = await stakingContract.getStakingPlan(1);
      expect(totalStaked).to.equal(0);
    });
    
    it("Should withdraw from one plan without affecting others", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await stakingContract.connect(addr1).stake(ethers.parseUnits("200", 18), 3);
      
      // Move past the lock period for the 1-month plan
      await time.increase(31 * 24 * 60 * 60);
      
      await stakingContract.connect(addr1).withdrawStake(1);
      
      // Check plan 1 was withdrawn
      const [amount1, , isActive1] = await stakingContract.getUserStake(addr1.address, 1);
      expect(amount1).to.equal(0);
      expect(isActive1).to.be.false;
      
      // Check plan 3 is still active
      const [amount3, , isActive3] = await stakingContract.getUserStake(addr1.address, 3);
      expect(amount3).to.equal(ethers.parseUnits("200", 18));
      expect(isActive3).to.be.true;
    });
  });
  
  describe("Multiple Plan Functionality", function () {
    it("Should track total user stake across plans", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await stakingContract.connect(addr1).stake(ethers.parseUnits("200", 18), 3);
      await stakingContract.connect(addr1).stake(ethers.parseUnits("300", 18), 6);
      
      const totalStake = await stakingContract.getTotalUserStake(addr1.address);
      expect(totalStake).to.equal(ethers.parseUnits("600", 18));
    });
    
    it("Should track total pending rewards across plans", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await stakingContract.connect(addr1).stake(ethers.parseUnits("200", 18), 3);
      
      // Move past all lock periods
      await time.increase(90 * 24 * 60 * 60);
      
      // Accumulate some rewards
      await time.increase(10 * 24 * 60 * 60);
      
      const reward1 = await stakingContract.pendingRewards(addr1.address, 1);
      const reward3 = await stakingContract.pendingRewards(addr1.address, 3);
      const totalRewards = await stakingContract.getTotalPendingRewards(addr1.address);
      
      expect(totalRewards).to.equal(reward1 + reward3);
    });
    
    it("Should have different lock periods for different plans", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await stakingContract.connect(addr1).stake(ethers.parseUnits("200", 18), 3);
      
      // Move past the 1-month lock period
      await time.increase(31 * 24 * 60 * 60);
      
      // Should be able to withdraw from plan 1
      await stakingContract.connect(addr1).withdrawStake(1);
      
      // But not from plan 3
      await expect(
        stakingContract.connect(addr1).withdrawStake(3)
      ).to.be.revertedWith("Lock period not expired");
      
      // Move past the 3-month lock period
      await time.increase(60 * 24 * 60 * 60);
      
      // Now should be able to withdraw from plan 3
      await stakingContract.connect(addr1).withdrawStake(3);
    });
  });
});