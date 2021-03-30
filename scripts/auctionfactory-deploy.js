const hre = require("hardhat");
const { ethers } = hre;
const BN = require("bn.js");

const D18 = ethers.BigNumber.from("1000000000000000000");
const DHT_TOTAL = ethers.BigNumber.from("20000000000000").mul(D18);

const fs = require("fs");
const overrides = {
  gasPrice: ethers.utils.parseUnits("1", "gwei"),
  gasLimit: 8000000,
};

async function main() {
  const [deployer, other1, other2, other3] = await ethers.getSigners();
  console.log("deployer address:", deployer.address);
  console.log("other1 address:", other1.address);
  console.log("other2 address:", other2.address);
  console.log("other3 address:", other3.address);
  const DHT = await ethers.getContractFactory("StakingToken");
  this.dht = await DHT.deploy("DHT", "DHT", 18, DHT_TOTAL, DHT_TOTAL);
  console.log("dht address:", this.dht.address);

  const dhtAmount = D18.mul(20000000);
  tx = await this.dht.mint(dhtAmount, overrides);
  await tx.wait(1);

  const AuctionFactory = await ethers.getContractFactory("AuctionFactory");
  this.auctionfactory = await AuctionFactory.deploy(
    deployer.address,
    overrides
  );
  console.log("factory address:", this.auctionfactory.address)
  tx = await this.auctionfactory.instantiate(123, "dht_swap", 1000, 1625035928, this.dht.address, overrides);
  await tx.wait(1);

  this.auction_addr = await this.auctionfactory.getAuction(123);
  console.log("auction pair address:", this.auction_addr)
  // await this.auction_addr.set_start_time(1616599208);
  // 向合约打入token
  tx = await this.dht.transfer(this.auction_addr, dhtAmount, overrides);
  await tx.wait(1);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
