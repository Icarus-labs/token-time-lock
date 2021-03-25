const hre = require("hardhat");
const { ethers } = hre;
const BN = require("bn.js");

const D18 = ethers.BigNumber.from("1000000000000000000");
const DHT_TOTAL = ethers.BigNumber.from("20000000000000").mul(D18);

const fs = require("fs");
const overrides = {
  gasPrice: ethers.utils.parseUnits("1.0", "gwei"),
};

async function main() {
  const [deployer, zeus, other1, other2, other3] = await ethers.getSigners();
  console.log("deployer address:", deployer.address);
  const DHT = await ethers.getContractFactory("StakingToken");
  this.dht = await DHT.deploy("DHT", "DHT", 18, DHT_TOTAL, DHT_TOTAL);
  console.log("dht address:", this.dht.address);

  const dhtAmount = D18.mul(20000000);
  tx = await this.dht.mint(dhtAmount, overrides);
  await tx.wait(1);

  const SwapImpl = await ethers.getContractFactory("SwapImpl");
  this.swapimpl = await SwapImpl.deploy("0x7465737400000000000000000000000000000000000000000000000000000000", "myswap", 1000, other2.address, this.dht.address);
  await this.swapimpl.set_start_time(1616599208);
  console.log("SwapImpl address", this.swapimpl.address);
  // 向合约打入token
  tx = await this.dht.transfer(this.swapimpl.address, dhtAmount, overrides);
  await tx.wait(1);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
