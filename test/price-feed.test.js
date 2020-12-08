const { expect } = require("chai");
const cryptoRandomString = require("crypto-random-string");
const BN = require("bn.js");
const { mineBlocks, getBlockNumber } = require("./helpers.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("all kinds of price feeds", function () {
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

    const PriceFeed = await ethers.getContractFactory("MiningEcoPriceFeed");
    const priceFeed = await PriceFeed.deploy([admin.address]);
    await priceFeed.feed(this.dada.address, "4500000"); // $0.045

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
    await this.miningEco.connect(platformManager).set_usdt(this.usdt.address);
    await this.miningEco
      .connect(platformManager)
      .set_template(0, projectFactory.address);

    await this.miningEco
      .connect(platformManager)
      .set_price_feed(priceFeed.address);

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

  it("constant price feed", async function () {
    const usdt_1 = new BN(10 ** 8);
    const token_amount = await this.miningEco.usdt_to_platform_token(
      usdt_1.toString()
    );
    const expected = new BN(1)
      .mul(new BN("1000000000000000000"))
      .mul(new BN("100000000"))
      .div(new BN("4500000"));
    expect(token_amount.toString()).to.equal(expected.toString());
  });
});
