const cryptoRandomString = require("crypto-random-string");
const { expect } = require("chai");
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("./helpers.js");

const D18 = new BN("1000000000000000000");
const D6 = new BN("100000000");
const DADA_TOTAL_SUPPLY = D18.mul(new BN("10000000000"));
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
      6,
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

    const ProjectFactory = await ethers.getContractFactory("ProjectFactory");
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

    this.balancePM = D18.mul(new BN(1000000000));
    await this.dada.mint(this.balancePM.toString());
    await this.dada.transfer(pm.address, this.balancePM.toString());
    this.balancePMusdt = D6.mul(new BN(100000));
    await this.usdt.mint(this.balancePMusdt.toString());
    await this.usdt.transfer(pm.address, this.balancePMusdt.toString());
    this.miningEco = this.miningEco.connect(pm);
    expect(await this.miningEco.initialized()).to.equal(true);
  });

  it("unknown template", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
    const min = D6.mul(new BN(800000));
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
        1000,
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
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
    const min = D6.mul(new BN(800000));
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
        1000,
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
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
    const min = D6.mul(new BN(800000));
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
        1000,
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
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000000));
    const min = D6.mul(new BN(20000));
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
        1000,
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
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    // pm dada balance is 10000
    const max = D6.mul(new BN(2000000));
    const min = D6.mul(new BN(20000));
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
        1000,
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
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
    const min = D6.mul(new BN(800000));
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
        1000,
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
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
    const min = D6.mul(new BN(800000));
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
        1000,
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

  it("create && succeed && claim bonus", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const Bonus = await ethers.getContractFactory("MiningEcoBonusBeta");
    const bonus = await Bonus.deploy(this.miningEco.address, this.dada.address);
    this.miningEco.connect(platformManager).set_bonus(bonus.address);
    const blockNumber = await getBlockNumber();
    const auditWindow = 50;
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
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
        100,
      ]
    );
    const facai = D18.mul(new BN("88888"));
    await this.dada.connect(admin).mint(facai.toString());
    await this.dada.connect(admin).transfer(bonus.address, facai.toString());
    await this.dada
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePMusdt.toString());
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
      .audit_project(projectId, true, 100);
    await mineBlocks(auditWindow);
    let project = await this.miningEco.projects(projectId);
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(17);
    await mineBlocks(7);
    await pt.heartbeat();
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt.mint(max.mul(new BN(2)).toString());
    await this.usdt.transfer(other.address, max.mul(new BN(2)).toString());
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());

    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal(
      max.toString()
    );
    expect(await projectTemplate.status()).to.equal(6);

    const pm_balance = await this.dada.balanceOf(pm.address);
    await mineBlocks(20);
    await this.miningEco.pay_insurance(projectId);

    expect(
      (
        await this.miningEco.usdt_to_platform_token(
          max.div(new BN(100)).toString()
        )
      ).toString()
    ).to.equal(
      pm_balance.sub(await this.dada.balanceOf(pm.address)).toString()
    );

    await bonus.connect(other).claim_investment_bonus(projectId);
    expect((await this.dada.balanceOf(other.address)).toString()).to.equal(
      facai.toString()
    );

    // expect(await projectTemplate.status()).to.equal(18);
    // await mineBlocks(30);

    // await pt.heartbeat();
    // expect(await projectTemplate.status()).to.equal(7); // Rolling
  });

  it("change insurance rate by audit", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const Bonus = await ethers.getContractFactory("MiningEcoBonusBeta");
    const bonus = await Bonus.deploy(this.miningEco.address, this.dada.address);
    this.miningEco.connect(platformManager).set_bonus(bonus.address);
    const blockNumber = await getBlockNumber();
    const auditWindow = 50;
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = D6.mul(new BN(1000000));
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
        100,
      ]
    );
    const facai = D18.mul(new BN("88888"));
    await this.dada.connect(admin).mint(facai.toString());
    await this.dada.connect(admin).transfer(bonus.address, facai.toString());
    await this.dada
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePMusdt.toString());
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
      .audit_project(projectId, true, 1000);
    await mineBlocks(auditWindow);
    let project = await this.miningEco.projects(projectId);
    let projectTemplate = ProjectTemplate.attach(project.addr);
    let pt = projectTemplate.connect(pm);
    expect(await projectTemplate.status()).to.equal(17);
    await mineBlocks(7);
    await pt.heartbeat();
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt.mint(max.mul(new BN(2)).toString());
    await this.usdt.transfer(other.address, max.mul(new BN(2)).toString());
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());

    expect((await this.usdt.balanceOf(pt.address)).toString()).to.equal(
      max.toString()
    );
    expect(await projectTemplate.status()).to.equal(6);

    const pm_balance = await this.dada.balanceOf(pm.address);
    await mineBlocks(20);
    const insurance_should = await this.miningEco.insurance(projectId);
    await this.miningEco.pay_insurance(projectId);

    expect(insurance_should).to.equal(
      pm_balance.sub(await this.dada.balanceOf(pm.address))
    );

    expect(
      (
        await this.miningEco.usdt_to_platform_token(
          max.div(new BN(10)).toString()
        )
      ).toString()
    ).to.equal(
      pm_balance.sub(await this.dada.balanceOf(pm.address)).toString()
    );
  });
});
