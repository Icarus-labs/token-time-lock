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
    const EthTokenSwap = await ethers.getContractFactory("EthTokenSwap");
    this.ethtokenswap = await EthTokenSwap.deploy("0x7465737400000000000000000000000000000000000000000000000000000000", "myswap", 1000, other3.address, this.dht.address);
    await this.ethtokenswap.set_start_time(1616599208);
    console.log("EthTokenSwap address", this.ethtokenswap.address);
    tx = await this.dht.transfer(this.ethtokenswap.address, dhtAmount, overrides);
    await tx.wait(1);

  });

  it("deploy uniswap", async function() {
    
  })
});
