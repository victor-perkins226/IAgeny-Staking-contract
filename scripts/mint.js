async function main() {
    // The address of the deployed StakingToken contract
    const stakingTokenAddress = "0x147ebdd7312595c00572fbddca0aae6615e80b76";
    
    // Get the contract instance
    const StakingToken = await ethers.getContractFactory("StakingToken");
    const stakingToken = await StakingToken.attach(stakingTokenAddress);
    
    // Amount to mint (for example, 1000 tokens with 18 decimals)
    const amountToMint = ethers.parseUnits("1000000", 18); // Adjust the amount as needed
    
    // Address to receive the minted tokens
    const recipientAddress = "0x8A131a003F57d48329E9240C3885f330695ED930"; // Replace with the address you want to mint to
    
    console.log("Minting tokens...");
    const mintTx = await stakingToken.mint(recipientAddress, amountToMint);
    await mintTx.wait();
    
    console.log(`Successfully minted ${ethers.formatUnits(amountToMint, 18)} tokens to ${recipientAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
