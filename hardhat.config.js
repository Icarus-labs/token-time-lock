require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {},
    ropsten: {
      chainId: 3,
      url: "https://ropsten.infura.io/v3/e468cafc35eb43f0b6bd2ab4c83fa688",
      accounts: [
        "0ac5211d9a97558e0a929d2b33cb33fd8def2970a9315dc093871b405a64207d", // me
        "fcd09fc317b13cdf6603bb93853db7e53316bc7c9dc6d4f2cfac1fd093df2f6b", // bobo
      ],
    },
  },
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
};
