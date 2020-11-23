const cryptoRandomString = require("crypto-random-string");
const { expect } = require("chai");

describe("Proxy", function () {
  beforeEach(async function () {
    const StakingToken = await ethers.getContractFactory("StakingToken");
    this.dada = await StakingToken.deploy(
      "DaDa",
      "DADA",
      "100000000000000000000000",
      "100000000000000000000000"
    );
  });

  it("deploy", async function () {
    const [admin, platformManager] = await ethers.getSigners();

    const MiningEco = await ethers.getContractFactory("MiningEco");
    const miningEco = await MiningEco.deploy();
    const miningEcoInitFragment = miningEco.interface.getFunction("initialize");
    const initializeCalldata = miningEco.interface.encodeFunctionData(
      miningEcoInitFragment,
      [this.dada.address, platformManager.address]
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
      "10000000000000000000000000",
      "10000000000000000000000000"
    );

    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const MiningEco = await ethers.getContractFactory("MiningEco");
    const miningEco = await MiningEco.deploy();
    const miningEcoInitFragment = miningEco.interface.getFunction("initialize");
    const initializeCalldata = miningEco.interface.encodeFunctionData(
      miningEcoInitFragment,
      [this.dada.address, platformManager.address]
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

    const initAmount = "50000000000000000000000";
    await this.dada.mint(initAmount);
    await this.dada.transfer(pm.address, initAmount);
    await this.dada.mint(initAmount);
    await this.dada.transfer(other.address, initAmount);
  });

  it("platform is initialized", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    expect(await miningEco.initialized()).to.equal(true);
  });

  it("create a new project", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    const miningEco = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction(
      "initialize(uint256,uint256,uint256,uint256,uint256,uint256,uint256,(uint256,uint256,uint256,uint256)[])"
    );
    const max = "1000000000000000000000000";
    const min = "800000000000000000000000";
    const raiseStart = 100;
    const raiseEnd = 200;
    const insuranceDeadline = 300;
    const repayDeadline = 1000;
    const profitRate = 1000;
    const phases = [[201, 202, "0", "1000000000000000000000000"]];
    const calldata = ProjectTemplate.interface.encodeFunctionData(
      initializeFrgmt,
      [
        raiseStart,
        raiseEnd,
        min,
        max,
        insuranceDeadline,
        repayDeadline,
        profitRate,
        phases,
      ]
    );
    await this.dada
      .connect(pm)
      .approve(miningEco.address, "50000000000000000000000");
    let sent = await miningEco.new_project(
      0,
      projectId,
      max,
      "test1",
      calldata
    );
    await sent.wait(1);
  });
});
