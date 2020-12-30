// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const { ethers } = hre;
const BN = require("bn.js");

const D18 = new BN("1000000000000000000");
const D8 = new BN("100000000");
const DADA_TOTAL_SUPPLY = D18.mul(new BN("10000000000000000000000"));
const USDT_TOTAL = D8.mul(new BN("10000000000000000000"));

const fs = require("fs");
const overrides = {
  gasPrice: ethers.utils.parseUnits("1.0", "gwei"),
};

async function main() {
  // const projectid =
  //   "0xfd7798d918799f5f1c7cc98a8900feb69d6a8cbb5dc8f036477fc4bca349e405";
  // const addr = "0xA47605cfdB95E2D3487375b896F55904af3cfD62";
  // const [pm] = await ethers.getSigners();
  // const MiningEco = await ethers.getContractFactory("MiningEco");
  // const miningEco = MiningEco.attach(addr);
  // await miningEco.audit_project(projectid, true);

  const MiningEco = await ethers.getContractFactory("MiningEco");
  const miningEco = MiningEco.attach(
    "0x5493c4738C05b16c9c147080766aa26aB3a9Ccff"
  );
  const data =
    "0xad3b9d8b000000000000000000000000000000000000000000000000000000000000000086987f96306a06d102a70cdc6d778aae1bc6ead1314aec98b55a603233e8730f000000000000000000000000000000000000000000000000000000174876e80000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000002626b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e48142951a0000000000000000000000009b2a19abd5624b5a5be25ed50f5022699d086ce70000000000000000000000000000000000000000000000000000000000001964000000000000000000000000000000000000000000000000000000174876e800000000000000000000000000000000000000000000000000000000174876e80000000000000000000000000000000000000000000000000000000000004eb58800000000000000000000000000000000000000000000000000000000000186a000000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000";
  const decoded = miningEco.interface.decodeFunctionData(
    miningEco.interface.getFunction("new_project"),
    data
  );
  console.log(decoded);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
