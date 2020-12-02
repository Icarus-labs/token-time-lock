// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const { ethers } = hre;
const BN = require("bn.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const [owner, platformManager, dara] = await ethers.getSigners();
  const StakingToken = await ethers.getContractFactory("StakingToken");
  const dada = await StakingToken.deploy(
    "DaDa Token",
    "DADA",
    DADA_TOTAL_SUPPLY.toString(),
    DADA_TOTAL_SUPPLY.toString()
  );
  console.log("DADA deployed to:", dada.address);
  const usdt = await StakingToken.deploy(
    "USDT",
    "USDT",
    USDT_TOTAL.toString(),
    USDT_TOTAL.toString()
  );
  console.log("USDT deployed to:", usdt.address);
  const MiningEco = await ethers.getContractFactory("MiningEco");
  const miningEco = await MiningEco.deploy();
  await miningEco.deployed();
  console.log("MiningEco deployed to:", miningEco.address);

  const Proxy = await ethers.getContractFactory("MiningEcoProxy");
  const proxy = await Proxy.deploy(miningEco.address, owner.address, []);
  console.log("MiningEcoProxy deployed to:", proxy.address);

  const ProjectFactory = await ethers.getContractFactory("ProjectFactory");
  const projectFactory = await ProjectFactory.deploy(
    proxy.address,
    usdt.address
  );
  console.log("Template deployed to:", projectFactory.address);

  const platform = MiningEco.attach(proxy.address).connect(platformManager);
  await platform.initialize(dada.address, usdt.address, owner.address);

  await platform.set_template(0, projectFactory.address);

  const dada_balance = new BN(5000000).mul(D18);
  await dada.mint(dada_balance.toString());
  // await dada.transfer(
  //   "0x4072Eb9f4985998d161b2424988e470e64c75f26",
  //   dada_balance.toString()
  // );
  const usdt_balance = USDT_TOTAL.div(new BN(100));
  await usdt.mint(usdt_balance.toString());
  // await usdt.transfer(
  //   "0x4072Eb9f4985998d161b2424988e470e64c75f26",
  //   usdt_balance.toString()
  // );

  console.log(
    `initial balances have been given to 0x92E73408801e713f8371f8A8c31a40130ae61a40`
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
