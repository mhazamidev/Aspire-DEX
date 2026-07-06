# AspireDEX — Contracts

Solidity contracts, tests and deployment scripts for the AspireDEX protocol, built with Hardhat.

## Contracts

**AMM (Uniswap V2-core-style, with oracle guard and per-pair circuit breaker):**
- `Factory.sol` — creates and indexes `Pair` contracts for token pairs (`createPair(tokenA, tokenB, baseFee, feeTo, protocolFeeBps)`)
- `Pair.sol` — the constant-product pool: reserves, TWAP oracle, dynamic fee, circuit breaker. Liquidity is provisioned the way Uniswap V2's *core* contract works — transfer tokens to the pair address, then call `mint`/`burn` directly (no periphery wrapper for this)
- `Router.sol` — quotes (`quoteExactInput`/`quoteExactOutput`) and executes swaps (`swapExactTokensForTokens`/`swapTokensForExactTokens`) with an oracle-deviation check and circuit-breaker guard. **It has no `addLiquidity`/`removeLiquidity`/`getAmountsOut` of its own** — see `AspireDEX.Blockchain/Services/DexBlockchainService.cs` for how the .NET layer provisions liquidity directly against `Pair` instead

**Lending protocol (Compound/Aave-style):**
- `LendingPool.sol` — deposits, borrows, repayments
- `InterestRateModel.sol` — utilization-based interest rate curve
- `LiquidationEngine.sol` — under-collateralized position liquidation
- `OracleHub.sol` — price feed aggregation for collateral valuation
- `RiskEngine.sol` — collateral factors, borrow limits, health-factor checks
- `PoolStorage.sol` — shared storage layout for the lending contracts

`contracts/test/MockERC20.sol` is a minimal ERC20 used for local testing and demos.

### ⚠️ Fixed: critical K-invariant bug in `Pair.swap`

`Pair.swap`'s constant-product check previously reverted only when the fee-adjusted balances
were *exactly equal* to the old reserves product — not when they were *less than* it. Since
exact equality essentially never happens with real fee-scaled arithmetic, the check was a
near no-op: a caller could request far more output than the constant-product formula allows
and the swap would still succeed, draining the pool. It's fixed now (`<` instead of `==`,
matching the standard Uniswap V2 `K` check) — see `test/Pair.ts`'s
`"reverts a swap that violates the constant-product invariant"` test.

## Commands

```shell
npm run compile         # hardhat compile (downloads a solc binary — see note below)
npm run compile:solcjs  # fallback: compiles with the pure-JS solc package, no binary download
npm run test            # hardhat test
node scripts/exportABI.cjs   # writes Factory/Pair/Router ABIs to ./abis for Nethereum codegen
```

**If `hardhat compile` fails with `HHE905: Couldn't download compiler version list`:** Hardhat
downloads a native solc binary from `binaries.soliditylang.org` on first compile, which some
networks/regions block. Options, in order of preference:
1. Run `npm run compile` once from a network that *can* reach that host (e.g. over a VPN) —
   Hardhat caches the binary afterwards, so every later compile works fully offline.
2. Use `npm run compile:solcjs` as a stand-in — it compiles with the `solc` npm package (pure
   JS/WASM, no extra network access beyond the initial `npm install`) via
   `scripts/solcjs-compile.cjs`, and prints the same errors/warnings `solc` would. It's not a
   full Hardhat build (no artifacts/typechain), so it's for a fast correctness check, not a
   replacement for `npm run compile` before deploying or running `npm test`.

There's no deployment script yet — `sepolia` is already configured in `hardhat.config.ts`
(reading `SEPOLIA_RPC_URL` / `SEPOLIA_PRIVATE_KEY` as Hardhat configuration variables), but a
`scripts/deploy.ts` still needs to be written. Tracked in the root README's roadmap.

The ABIs under `abis/` are consumed by `AspireDEX.Blockchain` on the .NET side via Nethereum's
contract-binding code generator (see `AspireDEX.Blockchain/nethereum-gen.settings.json`). Only
`Factory`, `Pair` and `Router` are exported/bound today — the lending protocol contracts aren't
wired into the ABI export or the C# layer yet.

## Tests

`test/` covers the AMM core with Hardhat + mocha + ethers:
- `Factory.ts` — pair creation, token-address sorting, `PairCreated`, duplicate/identical-token reverts
- `Pair.ts` — `MINIMUM_LIQUIDITY` lock-up, proportional mint/burn, the constant-product swap check (including the bug above)
- `Router.ts` — `quoteExactInput` against the fee-adjusted formula, a full swap moving real ERC20 balances, and the `Expired`/`InsufficientOutputAmount`/`InvalidPath` reverts

The lending protocol contracts don't have tests yet — tracked in the root README's roadmap.

## Status

The AMM contracts are integrated end-to-end with the .NET API and Blazor UI (see the root
[README](../README.md)) and now have a Hardhat test suite (above). The lending protocol
contracts exist here but don't yet have a C# integration layer or tests — tracked in the root
README's roadmap.
