const BN = require("bn.js");

async function getBlockNumber() {
  let provider = new ethers.providers.JsonRpcProvider();
  const number = new BN(
    (await provider.send("eth_blockNumber")).replace("0x", ""),
    16
  );
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
