const { expect } = require("chai");
const cryptoRandomString = require("crypto-random-string");
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("./helpers.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("TestProjectTemplate", function () {
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
    const ProjectFactory = await ethers.getContractFactory(
      "TestProjectFactory"
    );
    const projectFactory = await ProjectFactory.deploy(
      proxy.address,
      this.usdt.address
    );

    let tx = {
      to: proxy.address,
      data: ethers.utils.arrayify(initializeCalldata),
    };
    let sent = await platformManager.sendTransaction(tx);
    await sent.wait(1);

    this.miningEco = miningEco.attach(proxy.address);
    this.miningEco.connect(platformManager).set_usdt(this.usdt.address);
    this.miningEco
      .connect(platformManager)
      .set_template(0, projectFactory.address);

    this.balancePM = new BN(5000000).mul(D18);
    await this.dada.mint(this.balancePM.toString());
    await this.dada.transfer(pm.address, this.balancePM.toString());

    await this.usdt.mint(USDT_TOTAL.div(new BN(100)).toString());
    await this.usdt.transfer(
      other.address,
      USDT_TOTAL.div(new BN(100)).toString()
    );

    this.miningEco = this.miningEco.connect(pm);
  });

  it("missing replan window", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const raiseStart = blockNumber;
    const raiseEnd = blockNumber + 10;
    const phases = [
      [blockNumber + 40, blockNumber + 41, 80],
      [blockNumber + 50, blockNumber + 60, 20],
    ];
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
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
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    await pt.heartbeat();
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());
    await mineBlocks(10);
    await this.miningEco.pay_insurance(projectId);
    await mineBlocks(40);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_against_phase(1);
    expect(await projectTemplate.status()).to.equal(8);
    await mineBlocks(31);
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(11);
  });

  it("missing replan window & liquidate & project failed", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const raiseStart = blockNumber;
    const raiseEnd = blockNumber + 10;
    const phases = [
      [blockNumber + 40, blockNumber + 41, 80],
      [blockNumber + 50, blockNumber + 60, 20],
    ];
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
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
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    await pt.heartbeat();
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());
    await mineBlocks(10);
    await this.miningEco.pay_insurance(projectId);
    await mineBlocks(40);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_against_phase(1);
    expect(await projectTemplate.status()).to.equal(8);
    await mineBlocks(31);
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(11);
    const pre_balance = await this.usdt.balanceOf(other.address);
    await projectTemplate.connect(other).liquidate();
    expect(
      (await this.usdt.balanceOf(other.address)).sub(pre_balance).toString()
    ).to.equal(new BN(200000).mul(D18).toString());
    await pt.heartbeat();
    expect(await pt.status()).to.equal(5);
  });

  it("fail replan voting twice", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const raiseStart = blockNumber;
    const raiseEnd = blockNumber + 10;
    const phases = [
      [blockNumber + 40, blockNumber + 41, 80],
      [blockNumber + 50, blockNumber + 60, 20],
    ];
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
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
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    await pt.heartbeat();
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());
    await mineBlocks(10);
    await this.miningEco.pay_insurance(projectId);
    await mineBlocks(40);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_against_phase(1);
    const newPhases = [
      [blockNumber + 200, blockNumber + 210, 10],
      [blockNumber + 220, blockNumber + 230, 10],
    ];
    await pt.replan(newPhases);
    expect(await pt.status()).to.equal(8);
    await mineBlocks(40); // no votes means against
    await pt.heartbeat();
    expect((await pt.failed_replan_count()).toString()).to.equal("1");
    expect(await pt.status()).to.equal(10);
    await pt.replan(newPhases);
    await mineBlocks(40); // no votes means against
    await pt.heartbeat();
    expect((await pt.failed_replan_count()).toString()).to.equal("2");
    expect(await pt.status()).to.equal(11); // leads to liquidate
  });

  it("normal execution after replan", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const raiseStart = blockNumber;
    const raiseEnd = blockNumber + 10;
    const phases = [
      [blockNumber + 40, blockNumber + 41, 80],
      [blockNumber + 50, blockNumber + 60, 20],
    ];
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
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
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    await pt.heartbeat();
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());
    await mineBlocks(10);
    await this.miningEco.pay_insurance(projectId);
    await mineBlocks(40);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_against_phase(1);
    const newPhases = [
      [blockNumber + 100, blockNumber + 110, 10],
      [blockNumber + 120, blockNumber + 130, 10],
    ];
    await pt.replan(newPhases);
    await mineBlocks(20);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_for_replan();
    // await mineBlocks(70);
    // await pt.heartbeat();
    expect(await pt.status()).to.equal(7);
    // moving forward 2 phases directly
    await mineBlocks(70);
    await pt.heartbeat();
    // console.log(`current block: ${await getBlockNumber()}`);
    expect(await pt.status()).to.equal(12);
  });
});
