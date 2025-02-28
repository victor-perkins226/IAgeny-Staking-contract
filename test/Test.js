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
      const plan1 = await stakingContract.getStakingPlan(1);
      const plan3 = await stakingContract.getStakingPlan(3);
      const plan6 = await stakingContract.getStakingPlan(6);
      const plan12 = await stakingContract.getStakingPlan(12);

      expect(plan1.durationInSeconds).to.equal(planDurations.MONTH_1);
      expect(plan3.durationInSeconds).to.equal(planDurations.MONTH_3);
      expect(plan6.durationInSeconds).to.equal(planDurations.MONTH_6);
      expect(plan12.durationInSeconds).to.equal(planDurations.MONTH_12);

      expect(plan1.emissionRate).to.equal(emissionRates.MONTH_1);
      expect(plan3.emissionRate).to.equal(emissionRates.MONTH_3);
      expect(plan6.emissionRate).to.equal(emissionRates.MONTH_6);
      expect(plan12.emissionRate).to.equal(emissionRates.MONTH_12);
    });
  });

  describe("Staking Functionality", function () {
    it("Should allow staking tokens", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await expect(stakingContract.connect(addr1).stake(stakeAmount, 1))
        .to.emit(stakingContract, "Staked")
        .withArgs(addr1.address, stakeAmount, 1);

      const userStake = await stakingContract.getUserStake(addr1.address);
      expect(userStake.amount).to.equal(stakeAmount);
      expect(userStake.isActive).to.be.true;
    });

    it("Should allow additional stakes in same plan", async function () {
      const initialStake = ethers.parseUnits("100", 18);
      const additionalStake = ethers.parseUnits("50", 18);

      await stakingContract.connect(addr1).stake(initialStake, 1);
      await stakingContract.connect(addr1).stake(additionalStake, 1);

      const userStake = await stakingContract.getUserStake(addr1.address);
      expect(userStake.amount).to.equal(initialStake + additionalStake);
    });

    it("Should not allow staking in different plans simultaneously", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await expect(
        stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 3)
      ).to.be.revertedWith("Cannot stake in different plan");
    });
  });

  describe("Reward Distribution", function () {
    it("Should not distribute rewards before period completion", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      // Move forward 15 days (half period)
      await time.increase(15 * 24 * 60 * 60);

      const rewards = await stakingContract.pendingRewards(addr1.address);
      expect(rewards).to.equal(0);
    });

    it("Should distribute rewards after period completion", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      // Move forward 30 days (full period)
      await time.increase(30 * 24 * 60 * 60);

      const rewards = await stakingContract.pendingRewards(addr1.address);
      expect(rewards).to.be.gt(0);
    });

    it("Should distribute rewards proportionally between stakers", async function () {
      // addr1 stakes 100 tokens
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      // addr2 stakes 50 tokens
      await stakingContract.connect(addr2).stake(ethers.parseUnits("50", 18), 1);

      // Move forward 30 days
      await time.increase(30 * 24 * 60 * 60);

      const rewards1 = await stakingContract.pendingRewards(addr1.address);
      const rewards2 = await stakingContract.pendingRewards(addr2.address);

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

      // Move forward 25 days
      await time.increase(25 * 24 * 60 * 60);

      // addr2 stakes 5 days before period end
      await stakingContract.connect(addr2).stake(ethers.parseUnits("100", 18), 1);

      // Move forward 5 more days to complete period
      await time.increase(5 * 24 * 60 * 60);

      const rewards1 = await stakingContract.pendingRewards(addr1.address);
      const rewards2 = await stakingContract.pendingRewards(addr2.address);

      expect(rewards1).to.be.gt(0);
      expect(rewards2).to.be.gt(0);

      /* 
        25 days full payment + 5 days half payment = 27.5
        5 days half payment = 2.5
      */
     
      const ratio = rewards1 / rewards2;
      expect(ratio).to.be.equals(11n); 
    });
  });

  describe("Reward Withdrawal", function () {
    it("Should allow withdrawing rewards after period", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      // Complete one period
      await time.increase(30 * 24 * 60 * 60);

      const balanceBefore = await stakingToken.balanceOf(addr1.address);
      await stakingContract.connect(addr1).withdrawRewards();
      const balanceAfter = await stakingToken.balanceOf(addr1.address);

      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should reset pending rewards after withdrawal", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await time.increase(30 * 24 * 60 * 60);

      await stakingContract.connect(addr1).withdrawRewards();
      const userStake = await stakingContract.getUserStake(addr1.address);
      expect(userStake.rewards).to.equal(0);
    });
  });

  describe("Stake Withdrawal", function () {
    it("Should not allow withdrawal before lock period", async function () {
      await stakingContract.connect(addr1).stake(ethers.parseUnits("100", 18), 1);
      await expect(
        stakingContract.connect(addr1).withdrawStake()
      ).to.be.revertedWith("Lock period not expired");
    });

    it("Should allow withdrawal after lock period", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      // Move past lock period
      await time.increase(31 * 24 * 60 * 60);

      const balanceBefore = await stakingToken.balanceOf(addr1.address);
      await stakingContract.connect(addr1).withdrawStake();
      const balanceAfter = await stakingToken.balanceOf(addr1.address);

      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should update total staked amount after withdrawal", async function () {
      const stakeAmount = ethers.parseUnits("100", 18);
      await stakingContract.connect(addr1).stake(stakeAmount, 1);

      await time.increase(31 * 24 * 60 * 60);
      await stakingContract.connect(addr1).withdrawStake();

      const plan = await stakingContract.getStakingPlan(1);
      expect(plan.totalStaked).to.equal(0);
    });
  });
});