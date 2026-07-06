import { expect } from "chai";
import { network } from "hardhat";
import { deployFactoryWithPair, addLiquidity } from "./helpers.js";

const { ethers } = await network.connect();

describe("Pair", function () {
  const AMOUNT0 = 100_000n * 10n ** 18n;
  const AMOUNT1 = 400_000n * 10n ** 18n; // 1:4 ratio, arbitrary

  it("locks MINIMUM_LIQUIDITY and mints the rest to the first liquidity provider", async function () {
    const { deployer, pair, token0, token1 } = await deployFactoryWithPair();

    await addLiquidity(pair, token0, token1, AMOUNT0, AMOUNT1, deployer.address);

    const minimumLiquidity = await pair.MINIMUM_LIQUIDITY();
    const totalSupply = await pair.totalSupply();
    const deployerBalance = await pair.balanceOf(deployer.address);
    const deadBalance = await pair.balanceOf("0x000000000000000000000000000000000000dEaD");

    expect(deadBalance).to.equal(minimumLiquidity);
    expect(deployerBalance).to.equal(totalSupply - minimumLiquidity);

    // sqrt(AMOUNT0 * AMOUNT1) computed via Newton's method to cross-check the on-chain sqrt.
    const expectedTotal = isqrt(AMOUNT0 * AMOUNT1);
    expect(totalSupply).to.equal(expectedTotal);
  });

  it("updates reserves to match the tokens actually held after mint", async function () {
    const { pair, deployer, token0, token1 } = await deployFactoryWithPair();
    await addLiquidity(pair, token0, token1, AMOUNT0, AMOUNT1, deployer.address);

    const [reserve0, reserve1] = await pair.getReserves();
    expect(reserve0).to.equal(AMOUNT0);
    expect(reserve1).to.equal(AMOUNT1);
  });

  it("mints proportional liquidity for a second depositor at the same ratio", async function () {
    const { deployer, pair, token0, token1 } = await deployFactoryWithPair();
    await addLiquidity(pair, token0, token1, AMOUNT0, AMOUNT1, deployer.address);

    const totalSupplyBefore = BigInt(await pair.totalSupply());

    // Deposit exactly half of the existing reserves, at the same ratio.
    await addLiquidity(pair, token0, token1, AMOUNT0 / 2n, AMOUNT1 / 2n, deployer.address);

    const totalSupplyAfter = BigInt(await pair.totalSupply());
    const minted = totalSupplyAfter - totalSupplyBefore;

    // Proportional deposit → proportional LP mint (within 1 wei for integer rounding).
    const expectedMint = totalSupplyBefore / 2n;
    const diff = minted > expectedMint ? minted - expectedMint : expectedMint - minted;
    expect(diff).to.be.lessThanOrEqual(1n);
  });

  it("burns liquidity back into the underlying tokens proportionally", async function () {
    const { deployer, pair, token0, token1 } = await deployFactoryWithPair();
    await addLiquidity(pair, token0, token1, AMOUNT0, AMOUNT1, deployer.address);

    const pairAddress = await pair.getAddress();
    const lpBalance = await pair.balanceOf(deployer.address);
    const totalSupply = await pair.totalSupply();

    const balance0Before = await token0.balanceOf(deployer.address);
    const balance1Before = await token1.balanceOf(deployer.address);

    // Burn half of the LP position.
    const burnAmount = lpBalance / 2n;
    await pair.transfer(pairAddress, burnAmount);
    await pair.burn(deployer.address);

    const balance0After = await token0.balanceOf(deployer.address);
    const balance1After = await token1.balanceOf(deployer.address);

    const expectedAmount0 = (burnAmount * AMOUNT0) / totalSupply;
    const expectedAmount1 = (burnAmount * AMOUNT1) / totalSupply;

    expect(balance0After - balance0Before).to.equal(expectedAmount0);
    expect(balance1After - balance1Before).to.equal(expectedAmount1);
  });

  it("executes a swap respecting the constant-product invariant net of fees", async function () {
    const { deployer, pair, token0, token1 } = await deployFactoryWithPair(30); // 0.30% fee
    await addLiquidity(pair, token0, token1, AMOUNT0, AMOUNT1, deployer.address);

    const pairAddress = await pair.getAddress();
    const amountIn = 1_000n * 10n ** 18n;

    const [reserve0Before, reserve1Before] = await pair.getReserves();
    const feeDenominator = BigInt(await pair.FEE_DENOMINATOR());
    const totalFeeBps = BigInt(await pair.baseFee()) + BigInt(await pair.volatilityFee());

    // token0 -> token1: send token0 in, expect token1 out.
    const amountInWithFee = amountIn * (feeDenominator - totalFeeBps);
    const expectedOut =
      (amountInWithFee * reserve1Before) / (reserve0Before * feeDenominator + amountInWithFee);

    await token0.transfer(pairAddress, amountIn);
    await pair.swap(0, expectedOut, deployer.address, "0x");

    const [reserve0After, reserve1After] = await pair.getReserves();
    expect(reserve0After).to.equal(reserve0Before + amountIn);
    expect(reserve1After).to.equal(reserve1Before - expectedOut);
  });

  it("reverts a swap that violates the constant-product invariant (taking too much out)", async function () {
    const { deployer, pair, token0, token1 } = await deployFactoryWithPair(30);
    await addLiquidity(pair, token0, token1, AMOUNT0, AMOUNT1, deployer.address);

    const pairAddress = await pair.getAddress();
    const amountIn = 1_000n * 10n ** 18n;
    const [reserve0Before, reserve1Before] = await pair.getReserves();

    // Ask for far more out than the constant-product formula (net of fee) allows.
    const feeDenominator = BigInt(await pair.FEE_DENOMINATOR());
    const totalFeeBps = BigInt(await pair.baseFee()) + BigInt(await pair.volatilityFee());
    const amountInWithFee = amountIn * (feeDenominator - totalFeeBps);
    const maxOut =
      (amountInWithFee * reserve1Before) / (reserve0Before * feeDenominator + amountInWithFee);

    await token0.transfer(pairAddress, amountIn);
    await expect(pair.swap(0, maxOut + 1n, deployer.address, "0x")).to.be.revertedWithCustomError(
      pair,
      "InvalidK",
    );
  });
});

/** Integer square root via Newton's method — used only to cross-check on-chain Math.sqrt. */
function isqrt(value: bigint): bigint {
  if (value < 2n) return value;
  let x0 = value / 2n;
  let x1 = (x0 + value / x0) / 2n;
  while (x1 < x0) {
    x0 = x1;
    x1 = (x0 + value / x0) / 2n;
  }
  return x0;
}
