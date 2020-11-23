const { expect } = require("chai");
const cryptoRandomString = require("crypto-random-string");
const BN = require("bn.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");

describe("ProjectTemplate", function () {
  beforeEach(async function () {
    const StakingToken = await ethers.getContractFactory("StakingToken");
    this.dada = await StakingToken.deploy(
      "DaDa Token",
      "DADA",
      DADA_TOTAL_SUPPLY,
      DADA_TOTAL_SUPPLY
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

    const initAmount = new BN(5000).mul(D18);
    await this.dada.mint(initAmount);
    await this.dada.transfer(pm.address, initAmount);
    await this.dada.mint(initAmount);
    await this.dada.transfer(other.address, initAmount);

    const miningEcoPM = this.miningEco.connect(pm);
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const ProjectTemplate = await ethers.getContractFactory("ProjectTemplate");
    const initializeFrgmt = ProjectTemplate.interface.getFunction("initialize");
    const max = new BN("1000000000000000000000000");
    const min = max.mul(new BN(8)).div(new BN(10));
    const raiseStart = 100;
    const raiseEnd = 200;
    const insuranceDeadline = 300;
    const repayDeadline = 1000;
    const profitRate = 1000;
    const phases = [[100, 200, max.div(new BN(4))]];
    const replanGrants = [pm.address];
    const calldata = ProjectTemplate.interface.encodeFunctionData(
      initializeFrgmt,
      [
        pm.address,
        raiseStart,
        raiseEnd,
        min,
        max,
        insuranceDeadline,
        repayDeadline,
        profitRate,
        phases,
        replanGrants,
      ]
    );
    await this.dada
      .connect(pm)
      .approve(miningEcoPM.address, "50000000000000000000000");
    sent = await miningEcoPM.new_project(0, projectId, max, "test1", calldata);
    await sent.wait(1);
    let project = await miningEcoPM.projects(projectId);
    expect(project.owner).to.equal(pm.address);

    let projectTemplate = ProjectTemplate.attach(project.addr);
    expect(await projectTemplate.status()).to.equal(1);
  });

  it("", async function () {});
});
