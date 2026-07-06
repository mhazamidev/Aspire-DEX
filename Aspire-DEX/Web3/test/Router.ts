import { expect } from "chai";
import { network } from "hardhat";
import { ZERO_ADDRESS, deployFactoryWithPair, addLiquidity } from "./helpers.js";

const { ethers } = await network.connect();

describe("Router", function () {
  const AMOUNT0 = 100_000n * 10n ** 18n;
  const AMOUNT1 = 400_000n * 10n ** 18n;

  async function deployRouterFixture() {
    const base = await deployFactoryWithPair(30);
    await addLiquidity(base.pair, base.token0, base.token1, AMOUNT0, AMOUNT1, base.deployer.address);

    const Router = await ethers.getContractFactory("Router");
    // No oracle deployed for these tests — Router.oracle.getPriceSafe reverts on a
    // non-contract address, and Router's try/catch treats that as "skip validation".
    const router = await Router.deploy(await base.factory.getAddress(), ZERO_ADDRESS);

    return { ...base, router };
  }

  it("quoteExactInput matches the constant-product formula net of fees", async function () {
    const { router, pair, token0, token1 } = await deployRouterFixture();
    const amountIn = 1_000n * 10n ** 18n;

    const [reserve0, reserve1] = await pair.getReserves();
    const feeDenominator = BigInt(await pair.FEE_DENOMINATOR());
    const totalFeeBps = BigInt(await pair.baseFee()) + BigInt(await pair.volatilityFee());
    const amountInWithFee = amountIn * (feeDenominator - totalFeeBps);
    const expectedOut = (amountInWithFee * reserve1) / (reserve0 * feeDenominator + amountInWithFee);

    const path = [await token0.getAddress(), await token1.getAddress()];
    const amounts = await router.quoteExactInput(amountIn, path);

    expect(amounts[0]).to.equal(amountIn);
    expect(amounts[1]).to.equal(expectedOut);
  });

  it("swapExactTokensForTokens moves the input token in and the output token to the recipient", async function () {
    const { deployer, router, token0, token1 } = await deployRouterFixture();
    const amountIn = 1_000n * 10n ** 18n;
    const path = [await token0.getAddress(), await token1.getAddress()];

    const [expectedOut] = (await router.quoteExactInput(amountIn, path)).slice(1);
    const routerAddress = await router.getAddress();

    await token0.approve(routerAddress, amountIn);

    const balance0Before = await token0.balanceOf(deployer.address);
    const balance1Before = await token1.balanceOf(deployer.address);

    const deadline = (await ethers.provider.getBlock("latest"))!.timestamp + 600;
    await router.swapExactTokensForTokens(amountIn, expectedOut, path, deployer.address, deadline);

    const balance0After = await token0.balanceOf(deployer.address);
    const balance1After = await token1.balanceOf(deployer.address);

    expect(balance0Before - balance0After).to.equal(amountIn);
    expect(balance1After - balance1Before).to.equal(expectedOut);
  });

  it("reverts with InsufficientOutputAmount when amountOutMin isn't met", async function () {
    const { router, token0, token1, deployer } = await deployRouterFixture();
    const amountIn = 1_000n * 10n ** 18n;
    const path = [await token0.getAddress(), await token1.getAddress()];

    const [expectedOut] = (await router.quoteExactInput(amountIn, path)).slice(1);
    const routerAddress = await router.getAddress();
    await token0.approve(routerAddress, amountIn);

    const deadline = (await ethers.provider.getBlock("latest"))!.timestamp + 600;

    await expect(
      router.swapExactTokensForTokens(amountIn, expectedOut + 1n, path, deployer.address, deadline),
    ).to.be.revertedWithCustomError(router, "InsufficientOutputAmount");
  });

  it("reverts with Expired when the deadline has passed", async function () {
    const { router, token0, token1, deployer } = await deployRouterFixture();
    const amountIn = 1_000n * 10n ** 18n;
    const path = [await token0.getAddress(), await token1.getAddress()];

    const routerAddress = await router.getAddress();
    await token0.approve(routerAddress, amountIn);

    const pastDeadline = (await ethers.provider.getBlock("latest"))!.timestamp - 1;

    await expect(
      router.swapExactTokensForTokens(amountIn, 0, path, deployer.address, pastDeadline),
    ).to.be.revertedWithCustomError(router, "Expired");
  });

  it("reverts with InvalidPath for a single-token path", async function () {
    const { router, token0, deployer } = await deployRouterFixture();
    const deadline = (await ethers.provider.getBlock("latest"))!.timestamp + 600;

    await expect(
      router.swapExactTokensForTokens(1n, 0, [await token0.getAddress()], deployer.address, deadline),
    ).to.be.revertedWithCustomError(router, "InvalidPath");
  });
});
