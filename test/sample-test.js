const {expect} = require("chai");

describe("Proxy", function () {
  it("works", async function () {
    const [owner, other] = await ethers.getSigners();

    const MiningEco = await ethers.getContractFactory("MiningEco");
    const miningEco = await MiningEco.deploy();
    const miningEcoInitFragment = miningEco.interface.getFunction("initialize");
    const initializeCalldata = miningEco.interface.encodeFunctionData(
      miningEcoInitFragment,
      [
        "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        "0x92E73408801e713f8371f8A8c31a40130ae61a40",
      ]
    );

    expect(await miningEco.initialized.call()).equal(false);

    const Proxy = await ethers.getContractFactory("MiningEcoProxy");
    const proxy = await Proxy.deploy(miningEco.address, owner.address, []);

    let tx = {
      to: proxy.address,
      data: ethers.utils.arrayify(initializeCalldata),
    };
    await other.sendTransaction(tx);
  });
});
