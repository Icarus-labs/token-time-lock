const { expect } = require("chai");

const overrides = {
  gasPrice: ethers.utils.parseUnits("1", "gwei"),
  gasLimit: 8000000,
};

describe("DHT", function () {
  const D18 = ethers.BigNumber.from("1000000000000000000");
  const DHT_TOTAL = ethers.BigNumber.from("20000000000000").mul(D18);

  beforeEach(async function () {
    const [deployer, zeus, other1, other2, other3] = await ethers.getSigners();
    const DHT = await ethers.getContractFactory("StakingToken");
    this.dht = await DHT.deploy("DHT", "DHT", 18, DHT_TOTAL, DHT_TOTAL);
    console.log("dht address:", this.dht.address);

    const dhtAmount = D18.mul(20000000);
    tx = await this.dht.mint(dhtAmount, overrides);
    await tx.wait(1);

    // 向合约打入token
    const SwapImpl = await ethers.getContractFactory("SwapImpl");
    this.swapimpl = await SwapImpl.deploy("0x7465737400000000000000000000000000000000000000000000000000000000", "test", 1000, other2.address, this.dht.address);
    await this.swapimpl.set_start_time(1616599208);
    console.log("SwapImpl address", this.swapimpl.address);
    tx = await this.dht.transfer(this.swapimpl.address, dhtAmount, overrides);
    await tx.wait(1);

  

    // const BuyBack = await ethers.getContractFactory("BuyBack");
    // this.buyback = await BuyBack.deploy(D18.mul(10000), other2.address);
    // await this.buyback.addCaller(other1.address);

    // // 向other1注入usdt
    // tx = await this.usdt.mint(usdtAmount, overrides);
    // await tx.wait(1);
    // tx = await this.usdt.transfer(other1.address, usdtAmount, overrides);
    // await tx.wait(1);
    // await this.buyback.connect(other1.address).swap();
    // const balance = USDT_TOTAL.div(100);
    // {
    //   await this.usdt.mint(balance);
    //   await this.usdt.transfer(other1.address, balance);
    // }
    // {
    //   await this.usdt.mint(balance);
    //   await this.usdt.transfer(other2.address, balance);
    // }
    // {
    //   await this.usdt.mint(balance);
    //   await this.usdt.transfer(other3.address, balance);
    // }
  });

  it("deploy uniswap", async function() {
    
  })
});
