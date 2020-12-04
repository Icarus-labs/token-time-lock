const { expect } = require("chai");
const cryptoRandomString = require("crypto-random-string");
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("./helpers.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("ProjectTemplate illegal votes", function () {
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

    const [
      admin,
      platformManager,
      pm,
      other1,
      other2,
      other3,
    ] = await ethers.getSigners();
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
      other1.address,
      USDT_TOTAL.div(new BN(100)).toString()
    );
    await this.usdt.mint(USDT_TOTAL.div(new BN(100)).toString());
    await this.usdt.transfer(
      other2.address,
      USDT_TOTAL.div(new BN(100)).toString()
    );
    await this.usdt.mint(USDT_TOTAL.div(new BN(100)).toString());
    await this.usdt.transfer(
      other3.address,
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

  it("voting denial twice", async function () {
    const [
      admin,
      platformManager,
      pm,
      other1,
      other2,
      other3,
    ] = await ethers.getSigners();
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
    const raiseEnd = blockNumber + auditWindow + 30;
    const phases = [
      [blockNumber + auditWindow + 60, blockNumber + auditWindow + 61, 80],
      [blockNumber + auditWindow + 70, blockNumber + auditWindow + 80, 20],
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
    expect(project.owner).to.equal(pm.address);

    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(17);
    await mineBlocks(10);
    await pt.heartbeat();
    expect(await projectTemplate.status()).to.equal(2);
    await this.usdt
      .connect(other1)
      .approve(this.miningEco.address, max.toString());
    await this.miningEco
      .connect(other1)
      .invest(projectId, max.div(new BN(5)).toString());
    await this.usdt
      .connect(other2)
      .approve(this.miningEco.address, max.toString());
    await this.miningEco
      .connect(other2)
      .invest(projectId, max.div(new BN(5)).toString());
    await this.usdt
      .connect(other3)
      .approve(this.miningEco.address, max.toString());
    await this.miningEco.connect(other3).invest(projectId, max.toString());

    await mineBlocks(10);
    await this.miningEco.pay_insurance(projectId);
    await mineBlocks(40);
    await pt.heartbeat();
    expect(await projectTemplate.current_phase()).to.equal(1);

    await projectTemplate.connect(other1).vote_against_phase(1);
    await expect(
      projectTemplate.connect(other1).vote_against_phase(1)
    ).to.be.revertedWith("ProjectTemplate: account voted");
    await expect(
      projectTemplate.connect(other1).vote_phase(1, true)
    ).to.be.revertedWith("ProjectTemplate: account voted");
  });
});
