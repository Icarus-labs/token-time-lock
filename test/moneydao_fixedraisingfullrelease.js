const cryptoRandomString = require("crypto-random-string");
const { expect } = require("chai");
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("./helpers.js");

const D18 = new BN("1000000000000000000");
const D6 = new BN("100000000");
const DADA_TOTAL_SUPPLY = D18.mul(new BN("10000000000"));
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("MoneyDaoFixedRaisingFullRelease", function () {
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

    const MoneyDaoFactory = await ethers.getContractFactory(
      "MoneyDaoFixedRaisingFullReleaseFactory"
    );
    this.moneydaoFactory = await MoneyDaoFactory.deploy(
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
    this.miningEco.set_template(1, this.moneydaoFactory.address);

    await this.usdt.mint(USDT_TOTAL.div(new BN(100)).toString());
    await this.usdt.transfer(
      other.address,
      USDT_TOTAL.div(new BN(100)).toString()
    );

    this.balancePM = D18.mul(new BN(1000000000));
    await this.dada.mint(this.balancePM.toString());
    await this.dada.transfer(pm.address, this.balancePM.toString());
    this.balancePMusdt = D6.mul(new BN(100000000));
    await this.usdt.mint(this.balancePMusdt.toString());
    await this.usdt.transfer(pm.address, this.balancePMusdt.toString());
    this.miningEco = this.miningEco.connect(pm);
    expect(await this.miningEco.initialized()).to.equal(true);
  });

  it("life of a money dao fixed raising full release", async function () {
    const [
      admin,
      platformManager,
      pm,
      other,
      other1,
      other2,
    ] = await ethers.getSigners();
    const projectId = "0x" + cryptoRandomString({ length: 64 });
    const Template = await ethers.getContractFactory(
      "MoneyDaoFixedRaisingFullReleaseTemplate"
    );
    const initializeFrgmt = Template.interface.getFunction("initialize");
    const blockNumber = await getBlockNumber();
    const auditWindow = 50;
    const raiseStart = blockNumber + auditWindow + 10;
    const raiseEnd = blockNumber + auditWindow + 20;
    const max = D6.mul(new BN(1000000));
    const min = max.mul(new BN(8)).div(new BN(10));
    const repay_deadline = (await getBlockNumber()) + 1000;
    const profit_rate = 1000;
    const initializeCalldata = Template.interface.encodeFunctionData(
      initializeFrgmt,
      [
        pm.address,
        raiseStart,
        raiseEnd,
        min.toString(),
        max.toString(),
        repay_deadline,
        profit_rate,
        1000,
      ]
    );
    await this.dada
      .connect(pm)
      .approve(this.miningEco.address, this.balancePM.toString());
    await this.usdt
      .connect(pm)
      .approve(this.miningEco.address, this.balancePMusdt.toString());
    sent = await this.miningEco.new_project(
      1,
      projectId,
      max.toString(),
      "test1",
      initializeCalldata
    );
    await sent.wait(1);
    await this.miningEco
      .connect(platformManager)
      .audit_project(projectId, true, 1000);
    let project = await this.miningEco.projects(projectId);
    let moneydao = Template.attach(project.addr);
    moneydao = moneydao.connect(pm);
    expect(await moneydao.status()).to.equal(17);
    await mineBlocks(60);
    await moneydao.heartbeat();
    expect(await moneydao.status()).to.equal(2);
    const miningEcoOther = this.miningEco.connect(other);
    await this.usdt
      .connect(other)
      .approve(miningEcoOther.address, max.toString());
    await miningEcoOther.invest(projectId, max.toString());
    const pm_balance = await this.usdt.balanceOf(pm.address);
    await expect(this.miningEco.pay_insurance(projectId)).to.be.revertedWith(
      "MoneyDaoFixedRaisingFullReleaseTemplate: still in raising"
    );
    await mineBlocks(30);
    await this.miningEco.pay_insurance(projectId);
    expect(await moneydao.status()).to.equal(7);
    await moneydao.heartbeat();

    expect(await this.usdt.balanceOf(moneydao.address)).to.equal(
      ethers.BigNumber.from(0)
    );
    expect((await this.usdt.balanceOf(pm.address)).sub(pm_balance)).to.equal(
      ethers.BigNumber.from(max.toString())
    );

    await this.usdt
      .connect(pm)
      .approve(
        moneydao.address,
        max.mul(new BN(11)).div(new BN(10)).toString()
      );

    let _number = await getBlockNumber();
    let t = 0;
    if (_number <= repay_deadline) {
      t = repay_deadline - raiseEnd;
    } else {
      t = _number - raiseEnd;
    }
    const supposed_interest = max
      .mul(new BN(1000))
      .mul(new BN(t))
      .div(new BN(10000))
      .div(new BN(10 * 365));
    const supposed_repay = max.add(supposed_interest);

    await moneydao.fill_repay_tokens(
      max.mul(new BN(11)).div(new BN(10)).toString()
    );

    // repaying
    expect(await moneydao.actual_project_status()).to.equal(13);

    const balance_before_repay = await this.usdt.balanceOf(moneydao.address);
    await miningEcoOther.repay(projectId);
    expect(
      balance_before_repay
        .sub(await this.usdt.balanceOf(moneydao.address))
        .toString()
    ).to.equal(supposed_repay.toString());
    expect(await moneydao.actual_project_status()).to.equal(14);
    await moneydao.heartbeat();
    expect(await moneydao.status()).to.equal(14);
  });
});
