const cryptoRandomString = require("crypto-random-string");
const { expect } = require("chai");
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("./helpers.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const D8 = new BN("100000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("MiningEco create project", function () {
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
      [this.dada.address, this.usdt.address, platformManager.address]
    );

    const Proxy = await ethers.getContractFactory("MiningEcoProxy");
    const proxy = await Proxy.deploy(miningEco.address, admin.address, []);

    const ProjectFactory = await ethers.getContractFactory(
      "TestProjectFactory"
    );
    this.projectFactory = await ProjectFactory.deploy(
      proxy.address,
      this.usdt.address
    );

    let tx = {
      to: proxy.address,
      data: ethers.utils.arrayify(initializeCalldata),
    };
    let sent = await platformManager.sendTransaction(tx);
    await sent.wait(1);

    this.miningEco = miningEco.attach(proxy.address).connect(platformManager);
    expect(await this.miningEco.initialized()).to.equal(true);
    this.miningEco.set_template(0, this.projectFactory.address);

    this.balancePM = D18.mul(new BN(10000));
    await this.dada.mint(this.balancePM.toString());
    await this.dada.transfer(pm.address, this.balancePM.toString());
    this.balancePMusdt = D8.mul(new BN(10000));
    await this.usdt.mint(this.balancePMusdt.toString());
    await this.usdt.transfer(pm.address, this.balancePMusdt.toString());
    this.miningEco = this.miningEco.connect(pm);
    expect(await this.miningEco.initialized()).to.equal(true);
  });

  it("unknown template", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D8.mul(new BN(1000000));
    const min = D8.mul(new BN(800000));
    const blockNumber = await getBlockNumber();
    const raiseStart = blockNumber + 10;
    const raiseEnd = blockNumber + 20;
    const repayDeadline = blockNumber + 1000;
    const profitRate = 1000;
    const phases = [[blockNumber + 50, blockNumber + 51, 100]];
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
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await expect(
      this.miningEco.new_project(
        1,
        projectId,
        max.toString(),
        "test1",
        calldata
      )
    ).to.be.revertedWith("MiningEco: unknown template");
  });

  it("only one phase is not allowed", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D8.mul(new BN(1000000));
    const min = D8.mul(new BN(800000));
    const blockNumber = await getBlockNumber();
    const raiseStart = blockNumber + 10;
    const raiseEnd = blockNumber + 20;
    const repayDeadline = blockNumber + 1000;
    const profitRate = 1000;
    const phases = [[blockNumber + 50, blockNumber + 51, 100]];
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
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await expect(
      this.miningEco.new_project(
        0,
        projectId,
        max.toString(),
        "test1",
        calldata
      )
    ).to.be.revertedWith("ProjectTemplate: phase length");
  });

  it("phase boundaries across", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D8.mul(new BN(1000000));
    const min = D8.mul(new BN(800000));
    const blockNumber = await getBlockNumber();
    const raiseStart = blockNumber + 10;
    const raiseEnd = blockNumber + 20;
    const repayDeadline = blockNumber + 1000;
    const profitRate = 1000;
    const phases = [
      [blockNumber + 50, blockNumber + 60, 80],
      [blockNumber + 59, blockNumber + 70, 20],
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
      ]
    );
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await expect(
      this.miningEco.new_project(
        0,
        projectId,
        max.toString(),
        "test1",
        calldata
      )
    ).to.be.revertedWith("ProjectTemplate: phase boundaries across");
  });

  it("insufficient creation fee", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D8.mul(new BN(1000000000));
    const min = D8.mul(new BN(20000));
    const blockNumber = await getBlockNumber();
    const raiseStart = blockNumber + 10;
    const raiseEnd = blockNumber + 20;
    const repayDeadline = blockNumber + 1000;
    const profitRate = 1000;
    const phases = [
      [blockNumber + 50, blockNumber + 60, 80],
      [blockNumber + 60, blockNumber + 70, 20],
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
      ]
    );
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await expect(
      this.miningEco.new_project(
        0,
        projectId,
        max.toString(),
        "test1",
        calldata
      )
    ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
  });

  it("not ready for insurance", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    // pm dada balance is 10000
    const max = D8.mul(new BN(2000000));
    const min = D8.mul(new BN(20000));
    const blockNumber = await getBlockNumber();
    const auditWindow = 50;
    const raiseStart = blockNumber + auditWindow + 10;
    const raiseEnd = blockNumber + auditWindow + 20;
    const repayDeadline = blockNumber + auditWindow + 1000;
    const profitRate = 1000;
    const phases = [
      [blockNumber + auditWindow + 50, blockNumber + auditWindow + 60, 80],
      [blockNumber + auditWindow + 60, blockNumber + auditWindow + 70, 20],
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
      ]
    );
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await this.miningEco.new_project(
      0,
      projectId,
      max.toString(),
      "test1",
      calldata
    );
    await expect(this.miningEco.pay_insurance(projectId)).to.be.revertedWith(
      "MiningEco: not succeeded for insurance"
    );
  });

  it("not 100 percent", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D8.mul(new BN(1000000));
    const min = D8.mul(new BN(800000));
    const blockNumber = await getBlockNumber();
    const raiseStart = blockNumber + 10;
    const raiseEnd = blockNumber + 20;
    const repayDeadline = blockNumber + 1000;
    const profitRate = 1000;
    const phases = [
      [blockNumber + 50, blockNumber + 60, 80],
      [blockNumber + 60, blockNumber + 70, 10],
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
      ]
    );
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await expect(
      this.miningEco.new_project(
        0,
        projectId,
        max.toString(),
        "test1",
        calldata
      )
    ).to.be.revertedWith("ProjectTemplate: not 100 percent");
  });

  it("wrong phase duration", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory(
      "TestProjectTemplate"
    );
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D8.mul(new BN(1000000));
    const min = D8.mul(new BN(800000));
    const blockNumber = await getBlockNumber();
    const raiseStart = blockNumber + 10;
    const raiseEnd = blockNumber + 20;
    const repayDeadline = blockNumber + 1000;
    const profitRate = 1000;
    const phases = [
      [blockNumber + 50, blockNumber + 60, 80],

      [blockNumber + 80, blockNumber + 70, 20],
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
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
        0,
      ]
    );
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await expect(
      this.miningEco.new_project(
        0,
        projectId,
        max.toString(),
        "test1",
        calldata
      )
    ).to.be.revertedWith("ProjectTemplate: phase boundaries across");
  });
});
