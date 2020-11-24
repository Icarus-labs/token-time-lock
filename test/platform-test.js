const cryptoRandomString = require("crypto-random-string");
const { expect } = require("chai");
const BN = require("bn.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("Proxy", function () {
  beforeEach(async function () {
    const StakingToken = await ethers.getContractFactory("StakingToken");
    this.dada = await StakingToken.deploy(
      "DaDa",
      "DADA",
      DADA_TOTAL_SUPPLY,
      DADA_TOTAL_SUPPLY
    );
    this.usdt = await StakingToken.deploy(
      "USDT",
      "USDT",
      USDT_TOTAL.toString(),
      USDT_TOTAL.toString()
    );
  });

  it("deploy", async function () {
    const [admin, platformManager] = await ethers.getSigners();

    const MiningEco = await ethers.getContractFactory("MiningEco");
    const miningEco = await MiningEco.deploy();
    const miningEcoInitFragment = miningEco.interface.getFunction("initialize");
    const initializeCalldata = miningEco.interface.encodeFunctionData(
      miningEcoInitFragment,
      [this.dada.address, this.usdt.address, platformManager.address]
    );

    expect(await miningEco.initialized.call()).equal(false);

    const Proxy = await ethers.getContractFactory("MiningEcoProxy");
    const proxy = await Proxy.deploy(miningEco.address, admin.address, []);

    let tx = {
      to: proxy.address,
      data: ethers.utils.arrayify(initializeCalldata),
    };
    let sent = await platformManager.sendTransaction(tx);
    expect((await sent.wait(1)).status).to.equal(1);
  });
});

describe("MiningEco", function () {
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

    this.balancePM = D18.mul(new BN(10000));
    await this.dada.mint(this.balancePM.toString());
    await this.dada.transfer(pm.address, this.balancePM.toString());
  });

  it("platform is initialized", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    expect(await miningEco.initialized()).to.equal(true);
  });

  it("only one phase is not allowed", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = D18.mul(new BN(800000));
    const raiseStart = 100;
    const raiseEnd = 200;
    const insuranceDeadline = 300;
    const repayDeadline = 1000;
    const profitRate = 1000;
    const phases = [[201, 202, 100]];
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
      .approve(miningEco.address, this.balancePM.toString());
    await expect(
      miningEco.new_project(0, projectId, max.toString(), "test1", calldata)
    ).to.be.reverted;
  });

  it("phases across", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = D18.mul(new BN(800000));
    const raiseStart = 100;
    const raiseEnd = 200;
    const insuranceDeadline = 300;
    const repayDeadline = 1000;
    const profitRate = 1000;
    const phases = [
      [201, 210, 80],
      [209, 220, 20],
    ];
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
      .approve(miningEco.address, this.balancePM.toString());
    await expect(
      miningEco.new_project(0, projectId, max.toString(), "test1", calldata)
    ).to.be.reverted;
  });

  it("insufficient creation fee", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000000));
    const min = D18.mul(new BN(20000));
    const raiseStart = 100;
    const raiseEnd = 200;
    const insuranceDeadline = 300;
    const repayDeadline = 1000;
    const profitRate = 1000;
    const phases = [
      [201, 210, 80],
      [220, 230, 20],
    ];
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
      .approve(miningEco.address, this.balancePM.toString());
    await expect(
      miningEco.new_project(0, projectId, max.toString(), "test1", calldata)
    ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
  });

  it("insufficient insurance", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    // pm dada balance is 10000
    const max = D18.mul(new BN(2000000));
    const min = D18.mul(new BN(20000));
    const raiseStart = 100;
    const raiseEnd = 200;
    const insuranceDeadline = 300;
    const repayDeadline = 1000;
    const profitRate = 1000;
    const phases = [
      [201, 210, 80],
      [220, 230, 20],
    ];
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
      .approve(miningEco.address, this.balancePM.toString());
    await expect(
      miningEco.new_project(0, projectId, max.toString(), "test1", calldata)
    ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
  });

  it("total amount", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = D18.mul(new BN(800000));
    const raiseStart = 100;
    const raiseEnd = 200;
    const insuranceDeadline = 300;
    const repayDeadline = 1000;
    const profitRate = 1000;
    const phases = [
      [201, 210, 80],
      [220, 230, 10],
    ];
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
      .approve(miningEco.address, this.balancePM.toString());
    await expect(
      miningEco.new_project(0, projectId, max.toString(), "test1", calldata)
    ).to.be.reverted;
  });

  it("wrong phase duration", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D18.mul(new BN(1000000));
    const min = D18.mul(new BN(800000));
    const raiseStart = 100;
    const raiseEnd = 200;
    const insuranceDeadline = 300;
    const repayDeadline = 1000;
    const profitRate = 1000;
    const phases = [
      [201, 210, 80],
      [250, 230, 20],
    ];
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
      .approve(miningEco.address, this.balancePM.toString());
    await expect(
      miningEco.new_project(0, projectId, max.toString(), "test1", calldata)
    ).to.be.reverted;
  });
});
