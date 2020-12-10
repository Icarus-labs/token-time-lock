const cryptoRandomString = require("crypto-random-string");
const { expect } = require("chai");
const BN = require("bn.js");

const DADA_TOTAL_SUPPLY = new BN("10000000000000000000000000");
const D18 = new BN("1000000000000000000");
const D8 = new BN("100000000");
const USDT_TOTAL = new BN("1000000000000000000000000000000000000000000");

describe("Proxy", function () {
  beforeEach(async function () {
    const StakingToken = await ethers.getContractFactory("StakingToken");
    this.dada = await StakingToken.deploy(
      "DaDa",
      "DADA",
      18,
      DADA_TOTAL_SUPPLY,
      DADA_TOTAL_SUPPLY
    );
    this.usdt = await StakingToken.deploy(
      "USDT",
      "USDT",
      8,
      USDT_TOTAL.toString(),
      USDT_TOTAL.toString()
    );
  });

  it("deploy", async function () {
    const [admin, platformManager, pm] = await ethers.getSigners();

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

    this.miningEco = miningEco.attach(proxy.address).connect(pm);
  });

  it("platform is initialized", async function () {
    const [admin, platformManager, pm, other] = await ethers.getSigners();
    expect(await this.miningEco.initialized()).to.equal(true);
  });

  it("only platform committee can set template", async function () {
    const [
      admin,
      platformManager,
      _1,
      _2,
      stranger,
    ] = await ethers.getSigners();
    await expect(
      this.miningEco
        .connect(stranger)
        .set_template(0, "0x1D593d12e15b752d2Dcf8D3f4aA1f504Fe8E530F")
    ).to.be.revertedWith("MiningEco: only committee");
    await this.miningEco
      .connect(platformManager)
      .set_template(0, "0x1D593d12e15b752d2Dcf8D3f4aA1f504Fe8E530F");
  });
});
