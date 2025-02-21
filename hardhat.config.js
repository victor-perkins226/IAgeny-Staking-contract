require("@nomicfoundation/hardhat-toolbox");
// require("@nomiclabs/hardhat-verify");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.20",
  networks: {
    // For local testing
    hardhat: {
    },
    // For testnet deployment (example with Sepolia)
    sepolia: {
      url: "https://ethereum-sepolia-rpc.publicnode.com",
      accounts: ["7668f4389170b836294467fe363444953dae95a50ebd9993b97616b2ad4b7197"]
    }
  },
  etherscan: {
    apiKey: "ZJBQ6ZYVCYES22SE71ZDTFC9V1ETPPW946"
  }
  // verify: {
  //   apiKey: "ZJBQ6ZYVCYES22SE71ZDTFC9V1ETPPW946"
  // }
};
