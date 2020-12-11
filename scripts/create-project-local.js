const hre = require("hardhat");
const cryptoRandomString = require("crypto-random-string");
const { ethers } = hre;
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("../test/helpers.js");

const D18 = new BN("1000000000000000000");
const D8 = new BN("100000000");
const DADA_TOTAL_SUPPLY = D18.mul(new BN("100000000000000000"));

const overrides = {
  gasPrice: ethers.utils.parseUnits("1.0", "gwei"),
};

const fs = require("fs");
const addrs = JSON.parse(
  fs.readFileSync("./scripts/address.json").toString().trim()
);

const balancePM = D18.mul(new BN("10000000000"));
const balancePMusdt = D8.mul(new BN("1000000"));

async function main() {
  const [
    owner,
    platformManager,
    projectManager,
    other1,
  ] = await ethers.getSigners();

  const projectId = "0x" + cryptoRandomString({ length: 64 });
  const ProjectTemplate = await ethers.getContractFactory(
    "TestProjectTemplate"
  );
  const MiningEco = await ethers.getContractFactory("MiningEco");
  const DADA = await ethers.getContractFactory("StakingToken");
  const USDT = await ethers.getContractFactory("StakingToken");

  const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
  const max = D8.mul(new BN(1000000));
  const min = max.mul(new BN(8)).div(new BN(10));
  {
    await DADA.attach(addrs.dada).connect(owner).mint(balancePM.toString());
    await DADA.attach(addrs.dada)
      .connect(owner)
      .transfer(projectManager.address, balancePM.toString());
    await USDT.attach(addrs.usdt).connect(owner).mint(balancePMusdt.toString());
    await USDT.attach(addrs.usdt)
      .connect(owner)
      .transfer(projectManager.address, balancePMusdt.toString());
    await USDT.attach(addrs.usdt).connect(owner).mint(max.toString());
    await USDT.attach(addrs.usdt)
      .connect(owner)
      .transfer(other1.address, max.toString());
  }

  const blockNumber = await getBlockNumber();
  const auditWindow = 50;
  const profitRate = 1000;
  const raiseStart = blockNumber + auditWindow + 10;
  const raiseEnd = blockNumber + auditWindow + 20;
  const phases = [
    [blockNumber + auditWindow + 50, blockNumber + auditWindow + 51, 80],
    [blockNumber + auditWindow + 60, blockNumber + auditWindow + 70, 20],
  ];
  const repayDeadline = blockNumber + auditWindow + 1000;
  const replanGrants = [projectManager.address];
  const calldata = ProjectTemplate.interface.encodeFunctionData(
    initializeFrgmt,
    [
      projectManager.address,
      raiseStart,
      raiseEnd,
      min.toString(),
      max.toString(),
      repayDeadline,
      profitRate,
      phases,
      replanGrants,
      0,
    ]
  );
  await DADA.attach(addrs.dada)
    .connect(projectManager)
    .approve(addrs.miningeco, balancePM.toString());
  await USDT.attach(addrs.usdt)
    .connect(projectManager)
    .approve(addrs.miningeco, balancePMusdt.toString());
  sent = await MiningEco.attach(addrs.miningeco)
    .connect(projectManager)
    .new_project(0, projectId, max.toString(), "test1", calldata);
  await sent.wait(1);
  await MiningEco.attach(addrs.miningeco)
    .connect(platformManager)
    .audit_project(projectId, true);
  await mineBlocks(auditWindow + 10);
  let project = await MiningEco.attach(addrs.miningeco)
    .connect(other1)
    .projects(projectId);
  let projectTemplate = ProjectTemplate.attach(project.addr);
  let pt = projectTemplate.connect(projectManager);
  await pt.heartbeat();
  const miningEcoOther1 = MiningEco.attach(addrs.miningeco).connect(other1);
  await USDT.attach(addrs.usdt)
    .connect(other1)
    .approve(addrs.miningeco, max.toString());
  await miningEcoOther1.invest(projectId, max.toString());
  await mineBlocks(10);
  await MiningEco.attach(addrs.miningeco)
    .connect(projectManager)
    .pay_insurance(projectId);
  await mineBlocks(50);
  await pt.heartbeat();
  let _number = await getBlockNumber();
  await mineBlocks(repayDeadline - _number - 10);
  await USDT.attach(addrs.usdt)
    .connect(projectManager)
    .transfer(pt.address, max.div(new BN(10)).add(max).toString());
  await pt.heartbeat();
  await miningEcoOther1.repay(projectId);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
