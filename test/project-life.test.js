const { expect } = require("chai");
const cryptoRandomString = require("crypto-random-string");
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("./helpers.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("ProjectTemplate lifetime changes", function () {
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
    this.usdtPM = USDT_TOTAL.div(new BN(100));
    await this.usdt.mint(USDT_TOTAL.div(new BN(100)).toString());
    await this.usdt.transfer(
      pm.address,
      USDT_TOTAL.div(new BN(100)).toString()
    );
    this.miningEco = this.miningEco.connect(pm);
  });

  it("miss audit window", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
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
      .approve(this.miningEco.address, this.balancePM.toString());
    sent = await this.miningEco.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    let project = await this.miningEco.projects(projectId);
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(15);
    await mineBlocks(100);
    await projectTemplate.heartbeat();
    expect(await projectTemplate.status()).to.equal(5);
  });

  it("audit deny", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
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
      .approve(this.miningEco.address, this.balancePM.toString());
    sent = await this.miningEco.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    let project = await this.miningEco.projects(projectId);
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(15);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, false);
    expect(await projectTemplate.status()).to.equal(5);
  });

  it("audit pass", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
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
      .approve(this.miningEco.address, this.balancePM.toString());
    sent = await this.miningEco.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    let project = await this.miningEco.projects(projectId);
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(15);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true);
    expect(await projectTemplate.status()).to.equal(17);
  });

  it("first phase auto release", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
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
      .approve(this.miningEco.address, this.balancePM.toString());
    sent = await this.miningEco.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await sent.wait(1);
    let project = await this.miningEco.projects(projectId);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true);
    await mineBlocks(auditWindow + 10);
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());
    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal(
      max.toString()
    );
    expect(await projectTemplate.status()).to.equal(2);

    await mineBlocks(10);
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(6);

    await this.miningEco.pay_insurance(projectId);
    await mineBlocks(30);

    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(7);
    expect((await this.usdt.balanceOf(pm.address)).toString()).to.equal(
      max.mul(new BN(8)).div(new BN(10)).add(this.usdtPM).toString()
    );
    await mineBlocks(10);
    await pt.heartbeat();
    expect(await projectTemplate.current_phase()).to.equal(1);
  });

  it("voting to release", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const auditWindow = 50;
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
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
      .approve(this.miningEco.address, this.balancePM.toString());
    sent = await this.miningEco.new_project(
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
    await mineBlocks(auditWindow);
    let project = await this.miningEco.projects(projectId);
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(17);
    await mineBlocks(10);
    await pt.heartbeat();
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());

    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal(
      max.toString()
    );
    expect(await projectTemplate.status()).to.equal(2);

    await mineBlocks(20);
    await this.miningEco.pay_insurance(projectId);
    expect(await projectTemplate.status()).to.equal(18);
    await mineBlocks(30);

    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(7); // Rolling
    expect((await this.usdt.balanceOf(pm.address)).toString()).to.equal(
      max.mul(new BN(8)).div(new BN(10)).add(this.usdtPM).toString()
    );
    expect(await projectTemplate.current_phase()).to.equal(1);
    await mineBlocks(10);
    await pt.heartbeat();
    expect(await projectTemplate.current_phase()).to.equal(2);
    expect(await projectTemplate.status()).to.equal(12); //
    await pt.heartbeat();
    expect(await projectTemplate.current_phase()).to.equal(2);
    expect(await projectTemplate.status()).to.equal(12); //
    expect((await this.usdt.balanceOf(pm.address)).toString()).to.equal(
      max.add(this.usdtPM).toString()
    );
  });

  it("voting denial", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const auditWindow = 50;
    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
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
    await mineBlocks(auditWindow);
    let project = await miningEcoPM.projects(projectId);

    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(17);
    await mineBlocks(10);
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());

    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal(
      max.toString()
    );
    expect(await projectTemplate.status()).to.equal(2);

    await mineBlocks(10);
    await this.miningEco.pay_insurance(projectId);
    await mineBlocks(30);

    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(7); // Rolling
    expect((await this.usdt.balanceOf(pm.address)).toString()).to.equal(
      max.mul(new BN(8)).div(new BN(10)).add(this.usdtPM).toString()
    );
    await mineBlocks(10);
    await pt.heartbeat();
    expect(await projectTemplate.current_phase()).to.equal(1);

    await projectTemplate.connect(other).vote_against_phase(1);
    expect(await projectTemplate.current_phase()).to.equal(1);
    expect(await projectTemplate.status()).to.equal(8); //
  });

  it("replan", async function () {
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
    await mineBlocks(auditWindow);
    let project = await miningEcoPM.projects(projectId);

    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    await mineBlocks(10);
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
      [blockNumber + auditWindow + 110, blockNumber + auditWindow + 120, 10],
      [blockNumber + auditWindow + 130, blockNumber + auditWindow + 140, 10],
    ];

    await pt.replan(newPhases);
    await mineBlocks(20);
    await pt.heartbeat();
    expect(await pt.status()).to.equal(9);
    await projectTemplate.connect(other).vote_for_replan();
    expect(await pt.status()).to.equal(7);
    await mineBlocks(70);
    await pt.heartbeat();
    expect(await pt.current_phase()).to.equal(3);
    expect(await pt.status()).to.equal(12);
  });

  it("after all phase done", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
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
      .approve(this.miningEco.address, this.balancePM.toString());
    sent = await this.miningEco.new_project(
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
    await mineBlocks(auditWindow);
    let project = await this.miningEco.projects(projectId);
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    await pt.heartbeat();
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await mineBlocks(10);
    await miningEcoOther.invest(projectId, max.toString());
    await mineBlocks(10);
    await this.miningEco.pay_insurance(projectId);
    await mineBlocks(50);
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(12);
    let _number = await getBlockNumber();
    await mineBlocks(repayDeadline - _number - 10);
    await this.usdt
      .connect(pm)
      .transfer(pt.address, max.div(new BN(10)).add(max).toString());
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(13);
  });

  it("repay & finish", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const blockNumber = await getBlockNumber();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
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
      .approve(this.miningEco.address, this.balancePM.toString());
    sent = await this.miningEco.new_project(
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
    let project = await this.miningEco.projects(projectId);
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
    await mineBlocks(50);
    await pt.heartbeat();
    let _number = await getBlockNumber();
    await mineBlocks(repayDeadline - _number - 10);
    await this.usdt
      .connect(pm)
      .transfer(pt.address, max.div(new BN(10)).add(max).toString());
    await pt.heartbeat();
    await miningEcoOther.repay(projectId);
    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal("0");
    expect(await pt.status()).to.equal(13);
    await pt.heartbeat();
    expect(await pt.status()).to.equal(14);
  });
});
