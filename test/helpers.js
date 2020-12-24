const BN = require("bn.js");
const { ethers } = require("hardhat");

async function getBlockNumber() {
  let provider = new ethers.providers.JsonRpcProvider();
  const number = ethers.BigNumber.from(await provider.getBlockNumber());
  return number.toNumber();
}

async function mineBlocks(number) {
  let provider = new ethers.providers.JsonRpcProvider();
  for (let i = 0; i < number; i++) {
    await provider.send("evm_mine");
  }
}

module.exports = {
  getBlockNumber: getBlockNumber,
  mineBlocks: mineBlocks,
};
