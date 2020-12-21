const hre = require("hardhat");
const { ethers } = hre;
const BN = require("bn.js");

const D18 = new BN("1000000000000000000");
const D6 = new BN("1000000");
const DADA_TOTAL_SUPPLY = D18.mul(new BN("10000000000000000000000"));
const USDT_TOTAL = D6.mul(new BN("10000000000000000000"));

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
  await miningEco.set_price_feed("0x61Ffeb8D764b346A96b5f2f84C1FF362B38708ee");
  // const Contract = await ethers.getContractFactory("MiningEcoPriceFeedUniswap");
  // const contract = await Contract.deploy();
  // const contract = await Contract.attach(
  //   "0x6EC55b030B8b27F9167a5b0351A4D751a5Ae54dD"
  // );
  // const amt = await contract.from_usdt_to_token(
  //   D6.toString(),
  //   "0x54559aD7Ec464af2FC360B9405412eC8bB0F48Ed"
  // );
  // console.log(amt.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
