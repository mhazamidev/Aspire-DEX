import { network } from "hardhat";

const { ethers } = await network.connect();

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/** Sorts two token addresses the same way Factory does (token0 < token1). */
export function sortTokens(a: string, b: string): [string, string] {
  return a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a];
}

/**
 * Deploys Factory + two MockERC20 tokens + a Pair for them (with no protocol fee), and mints
 * an initial balance of both tokens to the given signer. Router is deployed separately (per
 * test file) since not every test needs it, and its constructor also wants an oracle address —
 * tests that don't care about oracle price validation can pass ZERO_ADDRESS, which makes
 * Router's oracle calls revert and get skipped (see Router._validateOraclePrice's try/catch).
 */
export async function deployFactoryWithPair(baseFeeBps = 30) {
  const [deployer] = await ethers.getSigners();

  const Factory = await ethers.getContractFactory("Factory");
  const factory = await Factory.deploy();

  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const tokenX = await MockERC20.deploy("Token X", "TKX");
  const tokenY = await MockERC20.deploy("Token Y", "TKY");

  const [token0Address, token1Address] = sortTokens(
    await tokenX.getAddress(),
    await tokenY.getAddress(),
  );

  await factory.createPair(token0Address, token1Address, baseFeeBps, ZERO_ADDRESS, 0);
  const pairAddress = await factory.getPair(token0Address, token1Address);
  const pair = await ethers.getContractAt("Pair", pairAddress);

  const token0 = await ethers.getContractAt("MockERC20", token0Address);
  const token1 = await ethers.getContractAt("MockERC20", token1Address);

  const initialMint = 1_000_000n * 10n ** 18n;
  await token0.mint(deployer.address, initialMint);
  await token1.mint(deployer.address, initialMint);

  return { deployer, factory, pair, token0, token1, tokenX, tokenY };
}

/** Adds liquidity the way this protocol actually works: transfer both tokens in, then mint. */
export async function addLiquidity(
  pair: Awaited<ReturnType<typeof ethers.getContractAt>>,
  token0: Awaited<ReturnType<typeof ethers.getContractAt>>,
  token1: Awaited<ReturnType<typeof ethers.getContractAt>>,
  amount0: bigint,
  amount1: bigint,
  to: string,
) {
  const pairAddress = await pair.getAddress();
  await token0.transfer(pairAddress, amount0);
  await token1.transfer(pairAddress, amount1);
  return pair.mint(to);
}
