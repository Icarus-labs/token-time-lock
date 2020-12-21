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
  const projectid =
    "0xfd7798d918799f5f1c7cc98a8900feb69d6a8cbb5dc8f036477fc4bca349e405";
  const addr = "0xA47605cfdB95E2D3487375b896F55904af3cfD62";
  const [pm] = await ethers.getSigners();
  const MiningEco = await ethers.getContractFactory("MiningEco");
  const miningEco = MiningEco.attach(addr);
  await miningEco.audit_project(projectid, true);
}
