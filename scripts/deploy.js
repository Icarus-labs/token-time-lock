// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const { ethers } = hre;

const D18 = ethers.BigNumber.from("1000000000000000000");
const D6 = ethers.BigNumber.from(1000000);
const D8 = ethers.BigNumber.from("100000000");
const BUSD_TOTAL = D18.mul(ethers.BigNumber.from("10000000000000000000"));
const ICA_TOTAL = D18.mul(ethers.BigNumber.from("100000000"));
const ZETH_TOTAL = D18.mul(1000000);
const BETH_TOTAL = D18.mul(100000000000);

const fs = require("fs");
const overrides = {
  gasPrice: ethers.utils.parseUnits("10", "gwei"),
  gasLimit: 8000000,
};

async function main() {
  const [deployer, zeus] = await ethers.getSigners();
  const Lock = await ethers.getContractFactory("TokenTimelock");

  let lock = await Lock.deploy("0x39B1d742f14c96a04467df63f27E477ff83C885E");
  await lock.deployed();
  console.log(lock.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
