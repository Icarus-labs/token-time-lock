const { expect } = require("chai");

const {
  getBlockTimestamp,
  setBlockTime,
  increaseTime,
  mineBlocks,
  sync: { getCurrentTimestamp },
} = require("./helpers.js");

const overrides = {
  gasPrice: ethers.utils.parseUnits("1", "gwei"),
  gasLimit: 8000000,
};

describe("DHT", function () {
  const D18 = ethers.BigNumber.from("1000000000000000000");
  const DHT_TOTAL = ethers.BigNumber.from("20000000000000").mul(D18);

  beforeEach(async function () {
    const [deployer, other1, other2, other3] = await ethers.getSigners();
    console.log("other1 address:", other1.address);
    const TOKEN1 = await ethers.getContractFactory("StakingToken");
    this.token1 = await TOKEN1.deploy("DHT", "DHT", 18, DHT_TOTAL, DHT_TOTAL);
    console.log("token1 address:", this.token1.address);

    const token1Amount = D18.mul(10000);
    tx = await this.token1.mint(token1Amount, overrides);
    await tx.wait(1);

    tx = await this.token1.transfer(other1.address, D18.mul(10000), overrides);
    await tx.wait(1);

    const TokenTimelock = await ethers.getContractFactory("TokenTimelock");
    this.tokentimelock = await TokenTimelock.deploy(this.token1.address, deployer.address);
    console.log("TokenTimelock address", this.tokentimelock.address);

    await this.token1.connect(other1).approve(this.tokentimelock.address, D18.mul(1000));
    expect(await this.token1.allowance(other1.address, this.tokentimelock.address)).to.eq(D18.mul(1000));

    await this.tokentimelock.connect(other1).send(D18.mul(5));
    expect(await this.token1.balanceOf(other1.address)).to.eq(D18.mul(9995));
    expect(await this.token1.balanceOf(this.tokentimelock.address)).to.eq(D18.mul(5));

    await increaseTime(3678400);
    await this.tokentimelock.connect(deployer).release();
    console.log(await this.tokentimelock.connect(deployer).releaseTime())
    expect(await this.token1.balanceOf(deployer.address)).to.eq(D18.mul(5));
  });

  it("deploy uniswap", async function() {
    
  })
});
