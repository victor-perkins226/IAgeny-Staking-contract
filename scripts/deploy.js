async function main() {
    const StakingToken = await ethers.getContractFactory("StakingToken");
    const contract = await ethers.getContractFactory("TokenStaking");
    
    // // Deploy first token
    console.log("Deploying staking token...");
    const token1 = await StakingToken.deploy("AGNT TOKEN", "AGNT");
    await token1.waitForDeployment();
    console.log("Staking token deployed to:", await token1.getAddress());
    const tokenAddress = await token1.getAddress();
    console.log("Deploying staking contract...");
    const stakingContract = await contract.deploy(tokenAddress, tokenAddress);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });