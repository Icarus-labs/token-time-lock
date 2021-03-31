const { expect } = require("chai");

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
    console.log("other2 address:", other2.address);
    const TOKEN1 = await ethers.getContractFactory("StakingToken");
    this.token1 = await TOKEN1.deploy("DHT", "DHT", 18, DHT_TOTAL, DHT_TOTAL);
    console.log("token1 address:", this.token1.address);
    const TOKEN2 = await ethers.getContractFactory("StakingToken");
    this.token2 = await TOKEN2.deploy("DHT", "DHT", 18, DHT_TOTAL, DHT_TOTAL);
    console.log("token2 address:", this.token2.address);

    const token1Amount = D18.mul(20000);
    tx = await this.token1.mint(token1Amount, overrides);
    await tx.wait(1);

    const token2Amount = D18.mul(20000000);
    tx = await this.token2.mint(token2Amount, overrides);
    await tx.wait(1);

    tx = await this.token1.transfer(other1.address, D18.mul(10000), overrides);
    await tx.wait(1);
    tx = await this.token1.transfer(other2.address, D18.mul(10000), overrides);
    await tx.wait(1);

    const TokenSwap = await ethers.getContractFactory("TokenSwap");
    this.tokenswap = await TokenSwap.deploy("0x7465737400000000000000000000000000000000000000000000000000000000", "myswap", 1000, other3.address, this.token1.address, this.token2.address);
    await this.tokenswap.set_start_time(1616599208);
    console.log("TokenSwap address", this.tokenswap.address);

    // 向合约打入token2
    tx = await this.token2.transfer(this.tokenswap.address, token2Amount, overrides);
    await tx.wait(1);

    await this.token1.connect(other1).approve(this.tokenswap.address, D18.mul(1000));
    expect(await this.token1.allowance(other1.address, this.tokenswap.address)).to.eq(D18.mul(1000));

    await this.tokenswap.connect(other1).swap(D18.mul(5));
    expect(await this.token1.balanceOf(other1.address)).to.eq(D18.mul(9995));
    expect(await this.token2.balanceOf(other1.address)).to.eq(D18.mul(5000));
    expect(await this.token1.balanceOf(this.tokenswap.address)).to.eq(D18.mul(5));
    expect(await this.token2.balanceOf(this.tokenswap.address)).to.eq(D18.mul(19995000));
  });

  it("deploy uniswap", async function() {
    
  })
});
