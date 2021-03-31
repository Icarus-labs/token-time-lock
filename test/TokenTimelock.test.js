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

describe("Simple Time Lock", function () {
  const D18 = ethers.BigNumber.from("1000000000000000000");
  const DHT_TOTAL = ethers.BigNumber.from("20000000000000").mul(D18);

  it("should works", async function() {
    const [deployer, other1, other2, other3] = await ethers.getSigners();
    const TOKEN1 = await ethers.getContractFactory("StakingToken");
    const token1 = await TOKEN1.deploy("DHT", "DHT", 18, DHT_TOTAL, DHT_TOTAL);

    const token1Amount = D18.mul(10000);
    tx = await token1.mint(token1Amount, overrides);
    await tx.wait(1);

    tx = await token1.transfer(other1.address, token1Amount, overrides);
    await tx.wait(1);

    const TokenTimelock = await ethers.getContractFactory("TokenTimelock");
    tokentimelock = await TokenTimelock.deploy(other1.address);

    tx = await token1.connect(other1).transfer(tokentimelock.address, token1Amount);
    await tx.wait(1);
    expect(await token1.balanceOf(other1.address)).to.eq(0);
    expect(await token1.balanceOf(tokentimelock.address)).to.eq(token1Amount);

    await increaseTime(86400);

    await expect(tokentimelock.release(token1.address)).to.be.revertedWith("TokenTimelock: current time is before release time");

    await increaseTime(86400 * 28);
    await expect(tokentimelock.release(token1.address)).to.be.revertedWith("TokenTimelock: current time is before release time");
    await increaseTime(86400);
    await tokentimelock.release(token1.address);
    expect(await token1.balanceOf(other1.address)).to.eq(token1Amount);
  });
});
