import { expect } from "chai";
import { network } from "hardhat";
import { ZERO_ADDRESS, sortTokens } from "./helpers.js";

const { ethers } = await network.connect();

describe("Factory", function () {
  async function deployFactoryAndTokens() {
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const tokenX = await MockERC20.deploy("Token X", "TKX");
    const tokenY = await MockERC20.deploy("Token Y", "TKY");

    return { factory, tokenX, tokenY };
  }

  it("creates a pair with tokens sorted the same way for both lookup directions", async function () {
    const { factory, tokenX, tokenY } = await deployFactoryAndTokens();
    const xAddress = await tokenX.getAddress();
    const yAddress = await tokenY.getAddress();
    const [token0, token1] = sortTokens(xAddress, yAddress);

    await factory.createPair(xAddress, yAddress, 30, ZERO_ADDRESS, 0);

    const pairAddress = await factory.getPair(xAddress, yAddress);
    expect(pairAddress).to.not.equal(ZERO_ADDRESS);
    expect(await factory.getPair(yAddress, xAddress)).to.equal(pairAddress);

    const pair = await ethers.getContractAt("Pair", pairAddress);
    expect(await pair.token0()).to.equal(token0);
    expect(await pair.token1()).to.equal(token1);
  });

  it("emits PairCreated with the sorted token addresses", async function () {
    const { factory, tokenX, tokenY } = await deployFactoryAndTokens();
    const xAddress = await tokenX.getAddress();
    const yAddress = await tokenY.getAddress();
    const [token0, token1] = sortTokens(xAddress, yAddress);

    const tx = await factory.createPair(xAddress, yAddress, 30, ZERO_ADDRESS, 0);
    const receipt = await tx.wait();

    const event = receipt!.logs
      .map((log: (typeof receipt.logs)[number]) => {
        try {
          return factory.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find((parsed: ReturnType<typeof factory.interface.parseLog>) => parsed?.name === "PairCreated");

    expect(event).to.not.be.undefined;
    expect(event!.args.token0).to.equal(token0);
    expect(event!.args.token1).to.equal(token1);
    expect(event!.args.pair).to.equal(await factory.getPair(xAddress, yAddress));
  });

  it("increments allPairsLength and records the pair in allPairs", async function () {
    const { factory, tokenX, tokenY } = await deployFactoryAndTokens();
    expect(await factory.allPairsLength()).to.equal(0n);

    await factory.createPair(await tokenX.getAddress(), await tokenY.getAddress(), 30, ZERO_ADDRESS, 0);

    expect(await factory.allPairsLength()).to.equal(1n);
    const pairAddress = await factory.getPair(await tokenX.getAddress(), await tokenY.getAddress());
    expect(await factory.allPairs(0)).to.equal(pairAddress);
  });

  it("reverts when creating a pair for a token with itself", async function () {
    const { factory, tokenX } = await deployFactoryAndTokens();
    const xAddress = await tokenX.getAddress();

    await expect(
      factory.createPair(xAddress, xAddress, 30, ZERO_ADDRESS, 0),
    ).to.be.revertedWith("Factory: IDENTICAL_ADDRESSES");
  });

  it("reverts when the pair already exists", async function () {
    const { factory, tokenX, tokenY } = await deployFactoryAndTokens();
    const xAddress = await tokenX.getAddress();
    const yAddress = await tokenY.getAddress();

    await factory.createPair(xAddress, yAddress, 30, ZERO_ADDRESS, 0);

    await expect(
      factory.createPair(xAddress, yAddress, 30, ZERO_ADDRESS, 0),
    ).to.be.revertedWith("Factory: PAIR_EXISTS");

    // Reversed order must also be rejected — it resolves to the same sorted pair.
    await expect(
      factory.createPair(yAddress, xAddress, 30, ZERO_ADDRESS, 0),
    ).to.be.revertedWith("Factory: PAIR_EXISTS");
  });
});
