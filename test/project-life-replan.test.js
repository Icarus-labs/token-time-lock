const { expect } = require("chai");
const cryptoRandomString = require("crypto-random-string");
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("./helpers.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const D6 = new BN("1000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("ProjectTemplate replan situations", function () {
  beforeEach(async function () {
    const StakingToken = await ethers.getContractFactory("StakingToken");
    this.dada = await StakingToken.deploy(
      "DaDa Token",
      "DADA",
      18,
      DADA_TOTAL_SUPPLY.toString(),
      DADA_TOTAL_SUPPLY.toString()
    );
    this.usdt = await StakingToken.deploy(
      "USDT",
      "USDT",
      8,
      USDT_TOTAL.toString(),
      USDT_TOTAL.toString()
    );

    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const MiningEco = await ethers.getContractFactory("MiningEco");
    const miningEco = await MiningEco.deploy();
    const miningEcoInitFragment = miningEco.interface.getFunction("initialize");
    const initializeCalldata = miningEco.interface.encodeFunctionData(
      miningEcoInitFragment,
      [
        this.dada.address,
        this.usdt.address,
        platformManager.address,
        platformManager.address,
      ]
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
    this.balancePMusdt = new BN(5000000).mul(D6);
    await this.usdt.mint(this.balancePMusdt.toString());
    await this.usdt.transfer(pm.address, this.balancePMusdt.toString());

    await this.usdt.mint(USDT_TOTAL.div(new BN(100)).toString());
    await this.usdt.transfer(
      other.address,
      USDT_TOTAL.div(new BN(100)).toString()
    );

    this.miningEco = this.miningEco.connect(pm);
  });

  it("replan between phases", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const auditWindow = 50;
    const profitRate = 1000;
    const raiseStart = blockNumber + auditWindow + 10;
    const raiseEnd = blockNumber + auditWindow + 20;
    const phases = [
      [blockNumber + auditWindow + 50, blockNumber + auditWindow + 51, 80],
      [blockNumber + auditWindow + 60, blockNumber + auditWindow + 70, 20],
    ];
    const repayDeadline = blockNumber + auditWindow + 1000;
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
    await this.usdt
      .connect(pm)
      .approve(miningEcoPM.address, this.balancePMusdt.toString());
    sent = await miningEcoPM.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true);
    await mineBlocks(auditWindow + 10);
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
    await mineBlocks(28);
    await pt.heartbeat();
    expect(await pt.status()).to.equal(7);
    let number = await getBlockNumber();
    expect(
      number >= blockNumber + auditWindow + 51 &&
        number < blockNumber + auditWindow + 60
    ).to.equal(true);

    const newPhases = [
      [blockNumber + auditWindow + 200, blockNumber + auditWindow + 210, 10],
      [blockNumber + auditWindow + 220, blockNumber + auditWindow + 230, 10],
    ];
    await pt.replan(newPhases);
    // await projectTemplate.connect(other).vote_against_phase(1);
    // expect(await projectTemplate.status()).to.equal(8);
    // await mineBlocks(31);
    // await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(16);
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
    const max = D6.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const auditWindow = 50;
    const profitRate = 1000;
    const raiseStart = blockNumber + auditWindow + 10;
    const raiseEnd = blockNumber + auditWindow + 20;
    const phases = [
      [blockNumber + auditWindow + 50, blockNumber + auditWindow + 51, 80],
      [blockNumber + auditWindow + 60, blockNumber + auditWindow + 70, 20],
    ];
    const repayDeadline = blockNumber + auditWindow + 1000;
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
    await this.usdt
      .connect(pm)
      .approve(miningEcoPM.address, this.balancePMusdt.toString());
    sent = await miningEcoPM.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true);
    await mineBlocks(auditWindow + 10);
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
    await mineBlocks(30);
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
    const max = D6.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const auditWindow = 50;
    const raiseStart = blockNumber + auditWindow + 10;
    const raiseEnd = blockNumber + auditWindow + 20;
    const phases = [
      [blockNumber + auditWindow + 50, blockNumber + auditWindow + 51, 80],
      [blockNumber + auditWindow + 60, blockNumber + auditWindow + 70, 20],
    ];
    const repayDeadline = blockNumber + auditWindow + 1000;
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
    await this.usdt
      .connect(pm)
      .approve(miningEcoPM.address, this.balancePMusdt.toString());
    sent = await miningEcoPM.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true);
    await mineBlocks(auditWindow + 10);
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
    await mineBlocks(38);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_against_phase(1);
    expect(await projectTemplate.status()).to.equal(8);
    await mineBlocks(31);
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(11);
    const pre_balance = await this.usdt.balanceOf(other.address);
    await miningEcoOther.liquidate(projectId);
    expect(
      (await this.usdt.balanceOf(other.address)).sub(pre_balance).toString()
    ).to.equal(new BN(200000).mul(D6).toString());
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
    const max = D6.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const auditWindow = 50;
    const raiseStart = blockNumber + auditWindow + 10;
    const raiseEnd = blockNumber + auditWindow + 20;
    const phases = [
      [blockNumber + auditWindow + 50, blockNumber + auditWindow + 51, 80],
      [blockNumber + auditWindow + 60, blockNumber + auditWindow + 70, 20],
    ];
    const repayDeadline = blockNumber + auditWindow + 1000;
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
    await this.usdt
      .connect(pm)
      .approve(miningEcoPM.address, this.balancePMusdt.toString());
    sent = await miningEcoPM.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true);
    await mineBlocks(auditWindow + 10);
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
    await mineBlocks(38);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_against_phase(1);
    const newPhases = [
      [blockNumber + auditWindow + 200, blockNumber + auditWindow + 210, 10],
      [blockNumber + auditWindow + 220, blockNumber + auditWindow + 230, 10],
    ];
    await pt.replan(newPhases);
    expect(await pt.status()).to.equal(16);
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
    const max = D6.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const auditWindow = 50;
    const raiseStart = blockNumber + auditWindow + 10;
    const raiseEnd = blockNumber + auditWindow + 20;
    const phases = [
      [blockNumber + auditWindow + 50, blockNumber + auditWindow + 51, 80],
      [blockNumber + auditWindow + 60, blockNumber + auditWindow + 70, 20],
    ];
    const repayDeadline = blockNumber + auditWindow + 1000;
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
    await this.usdt
      .connect(pm)
      .approve(miningEcoPM.address, this.balancePMusdt.toString());
    sent = await miningEcoPM.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true);
    await mineBlocks(auditWindow + 10);
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
    await mineBlocks(38);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_against_phase(1);
    const newPhases = [
      [blockNumber + auditWindow + 110, blockNumber + auditWindow + 120, 10],
      [blockNumber + auditWindow + 130, blockNumber + auditWindow + 140, 10],
    ];
    await pt.replan(newPhases);
    await mineBlocks(20);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_for_replan();
    // await mineBlocks(70);
    // await pt.heartbeat();
    expect(await pt.status()).to.equal(7);

    await mineBlocks(40);
    await pt.heartbeat();
    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal(
      max.div(new BN(10)).toString()
    );
    await mineBlocks(20);
    await pt.heartbeat();
    expect(await pt.status()).to.equal(12);
  });

  it("check replan auth", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const profitRate = 1000;
    const auditWindow = 50;
    const raiseStart = blockNumber + auditWindow + 10;
    const raiseEnd = blockNumber + auditWindow + 20;
    const phases = [
      [blockNumber + auditWindow + 50, blockNumber + auditWindow + 51, 80],
      [blockNumber + auditWindow + 60, blockNumber + auditWindow + 70, 20],
    ];
    const repayDeadline = blockNumber + auditWindow + 1000;
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
    await this.usdt
      .connect(pm)
      .approve(miningEcoPM.address, this.balancePMusdt.toString());
    sent = await miningEcoPM.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true);
    await mineBlocks(auditWindow + 10);
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
    await mineBlocks(38);
    await pt.heartbeat();
    await projectTemplate.connect(other).vote_against_phase(1);
    const newPhases = [
      [blockNumber + auditWindow + 110, blockNumber + auditWindow + 120, 10],
      [blockNumber + auditWindow + 130, blockNumber + auditWindow + 140, 10],
    ];
    await expect(
      projectTemplate.connect(other).replan(newPhases)
    ).to.be.revertedWith("ProjectTemplate: no replan auth");
  });
});
