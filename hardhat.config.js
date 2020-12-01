require("@nomiclabs/hardhat-waffle");

const fs = require("fs");
const infuraKey = "e468cafc35eb43f0b6bd2ab4c83fa688";
const privateKeys = JSON.parse(
  fs.readFileSync("test.secret.json").toString().trim()
);

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
      url: `https://ropsten.infura.io/v3/${infuraKey}`,
      accounts: privateKeys,
      timeout: 200000,
    },
    kovan: {
      chainId: 42,
      url: `https://kovan.infura.io/v3/${infuraKey}`,
      accounts: privateKeys,
      timeout: 200000,
    },
  },
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
    },
  },
  mocha: {
    timeout: 200000,
  },
};
