// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const { ethers, upgrades } = hre;

const { expect } = require("chai");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const [owner, other] = await ethers.getSigners();
  const MiningEco = await ethers.getContractFactory("MiningEco");
  const miningEco = await MiningEco.deploy();
  await miningEco.deployed();
  console.log("MiningEco deployed to:", miningEco.address);

  const Proxy = await ethers.getContractFactory("MiningEcoProxy");
  const proxy = await Proxy.deploy(miningEco.address, owner.address, []);
  console.log("MiningEcoProxy deployed to:", proxy.address);

  const miningEcoInitFragment = miningEco.interface.getFunction("initialize");
  const initializeCalldata = miningEco.interface.encodeFunctionData(
    miningEcoInitFragment,
    ["0xdAC17F958D2ee523a2206206994597C13D831ec7", owner.address] // token, vault
  );
  let tx = {
    to: proxy.address,
    data: ethers.utils.arrayify(initializeCalldata),
    gasPrice: 50000000000,
    gasLimit: 320000,
  };
  let res = await other.sendTransaction(tx);
  let receipt = await res.wait(1);
  console.log(
    "Platform initialization is called through proxy:",
    receipt.transactionHash
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
