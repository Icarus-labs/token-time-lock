const { expect } = require("chai");
const cryptoRandomString = require("crypto-random-string");
const BN = require("bn.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

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

describe("ProjectTemplate", function () {
  beforeEach(async function () {
    const StakingToken = await ethers.getContractFactory("StakingToken");
    this.dada = await StakingToken.deploy(
      "DaDa Token",
      "DADA",
      DADA_TOTAL_SUPPLY.toString(),
      DADA_TOTAL_SUPPLY.toString()
    );
    this.usdt = await StakingToken.deploy(
      "USDT",
      "USDT",
      USDT_TOTAL.toString(),
      USDT_TOTAL.toString()
    );

    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const MiningEco = await ethers.getContractFactory("MiningEco");
    const miningEco = await MiningEco.deploy();
    const miningEcoInitFragment = miningEco.interface.getFunction("initialize");
    const initializeCalldata = miningEco.interface.encodeFunctionData(
      miningEcoInitFragment,
      [this.dada.address, this.usdt.address, platformManager.address]
    );

    const Proxy = await ethers.getContractFactory("MiningEcoProxy");
    const proxy = await Proxy.deploy(miningEco.address, admin.address, []);

    let tx = {
      to: proxy.address,
      data: ethers.utils.arrayify(initializeCalldata),
    };
    let sent = await platformManager.sendTransaction(tx);
    await sent.wait(1);

    this.miningEco = miningEco.attach(proxy.address);
    this.miningEco.connect(platformManager).set_usdt(this.usdt.address);

    this.balancePM = new BN(5000000).mul(D18);
    await this.dada.mint(this.balancePM.toString());
    await this.dada.transfer(pm.address, this.balancePM.toString());

    await this.usdt.mint(USDT_TOTAL.div(new BN(100)).toString());
    await this.usdt.transfer(
      other.address,
      USDT_TOTAL.div(new BN(100)).toString()
    );
  });

  it("first phase auto release", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const raiseStart = blockNumber + 1;
    const raiseEnd = blockNumber + 10;
    const phases = [
      [blockNumber + 10, blockNumber + 11, 80],
      [blockNumber + 20, blockNumber + 30, 20],
    ];
    const insuranceDeadline = blockNumber + 300;
    const repayDeadline = blockNumber + 1000;
    const replanGrants = [pm.address];
    const calldata = ProjectTemplate.interface.encodeFunctionData(
      initializeFrgmt,
      [
        pm.address,
        raiseStart,
        raiseEnd,
        min.toString(),
        max.toString(),
        insuranceDeadline,
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
      ]
    );
    await this.dada
      .connect(pm)
      .approve(miningEcoPM.address, this.balancePM.toString());
    sent = await miningEcoPM.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    let project = await miningEcoPM.projects(projectId);
    expect(project.owner).to.equal(pm.address);

    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(1);

    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(2);

    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest_by_id(projectId, max.toString());

    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal(
      max.toString()
    );
    expect(await projectTemplate.status()).to.equal(2);

    await mineBlocks(10);
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(7); // Rolling
    expect((await this.usdt.balanceOf(pm.address)).toString()).to.equal(
      max.mul(new BN(8)).div(new BN(10)).toString()
    );
    await mineBlocks(10);
    expect(await projectTemplate.current_phase()).to.equal(1);
  });

  it("voting to release", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const raiseStart = blockNumber + 1;
    const raiseEnd = blockNumber + 10;
    const phases = [
      [blockNumber + 10, blockNumber + 11, 80],
      [blockNumber + 20, blockNumber + 30, 20],
    ];
    const insuranceDeadline = blockNumber + 300;
    const repayDeadline = blockNumber + 1000;
    const replanGrants = [pm.address];
    const calldata = ProjectTemplate.interface.encodeFunctionData(
      initializeFrgmt,
      [
        pm.address,
        raiseStart,
        raiseEnd,
        min.toString(),
        max.toString(),
        insuranceDeadline,
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
      ]
    );
    await this.dada
      .connect(pm)
      .approve(miningEcoPM.address, this.balancePM.toString());
    sent = await miningEcoPM.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    let project = await miningEcoPM.projects(projectId);
    expect(project.owner).to.equal(pm.address);

    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(1);

    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(2);

    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest_by_id(projectId, max.toString());

    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal(
      max.toString()
    );
    expect(await projectTemplate.status()).to.equal(2);

    await mineBlocks(10);
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(7); // Rolling
    expect((await this.usdt.balanceOf(pm.address)).toString()).to.equal(
      max.mul(new BN(8)).div(new BN(10)).toString()
    );
    await mineBlocks(10);
    expect(await projectTemplate.current_phase()).to.equal(1);
  });
});
