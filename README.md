# AspireDEX

A decentralized exchange built with **.NET Aspire**, **ASP.NET Core**, **Blazor Server**, **Nethereum** and **Solidity**.

Two on-chain protocols share this codebase:

- **AMM:** `Factory`, `Pair`, `Router` — a Uniswap V2-*core*-style constant-product pool with a
  TWAP oracle, dynamic fee and per-pair circuit breaker. Its `Router` only quotes and executes
  swaps (with an oracle-deviation guard) — it has no `addLiquidity`/`removeLiquidity` of its
  own, so liquidity is provisioned directly against `Pair` (transfer tokens in, then mint/burn),
  the same way Uniswap V2's core contract works.
- **Lending protocol (Compound/Aave-style):** `LendingPool`, `InterestRateModel`, `LiquidationEngine`, `OracleHub`, `RiskEngine`, `PoolStorage`.

The AMM side is wired end-to-end (contracts → Nethereum service layer → API → Blazor UI) and has
a Hardhat test suite. The lending protocol currently exists as Solidity contracts under
`Web3/contracts` without a C# integration layer or tests yet — see [Roadmap](#roadmap).

> **⚠️ Security fix:** `Pair.swap`'s constant-product check previously reverted only on *exact
> equality* with the old reserves product instead of on *insufficient* output — which meant it
> provided essentially no protection against draining a pool. Fixed — see `Web3/README.md` for
> details and the regression test that covers it.

## Architecture

```
Web3/                      Hardhat + Solidity (AMM + lending contracts, ABIs, deployment scripts)
Aspire-DEX/
├── AspireDEX.AppHost        .NET Aspire orchestrator — wires services together, injects secrets
├── AspireDEX.ServiceDefaults Shared health checks / telemetry / service-discovery defaults
├── AspireDEX.Blockchain     Nethereum contract bindings + DexBlockchainService (reads & writes)
├── AspireDEX.ApiService     Minimal API exposing pools/swap/liquidity endpoints
└── AspireDEX.Web            Blazor Server UI (Pools, Swap, Liquidity pages)
```

`AspireDEX.Web` never talks to the chain directly — it calls `AspireDEX.ApiService` over HTTP
(via Aspire service discovery), which is the only layer holding a Web3 connection.

**Demo architecture note:** write operations (swap, add/remove liquidity) are currently signed
by a single operator account configured on the API service, not by each visitor's own wallet.
This is intentional for a first milestone — see [Roadmap](#roadmap) for wallet-based signing.

## Tech stack

- .NET 10 / ASP.NET Core Minimal APIs / Blazor Server
- .NET Aspire (service orchestration, service discovery, secret parameters, health checks)
- Nethereum (Web3 client + code-generated contract bindings)
- Solidity + Hardhat + TypeScript (contracts, tests, deployment scripts)
- Redis (output caching for the web frontend)

## Running locally

Prerequisites: .NET 10 SDK, Docker (for Aspire's Redis container), an Ethereum RPC endpoint
(a public Sepolia testnet endpoint works out of the box), and deployed Router/Factory contract
addresses. `Web3/hardhat.config.ts` already has a `sepolia` network configured — a deployment
script (`scripts/deploy.ts`) still needs to be written; see [Roadmap](#roadmap). Until then, run
the contracts against a local Hardhat node for end-to-end testing.

Set the blockchain configuration as Aspire user-secrets on the AppHost project — this keeps the
private key out of source control and out of `appsettings.json`:

```bash
cd Aspire-DEX/AspireDEX.AppHost
dotnet user-secrets set "Parameters:blockchain-rpc-url" "https://ethereum-sepolia-rpc.publicnode.com"
dotnet user-secrets set "Parameters:blockchain-private-key" "0xyour_test_account_private_key"
dotnet user-secrets set "Parameters:blockchain-chain-id" "11155111"
dotnet user-secrets set "Parameters:router-address" "0xDeployedRouterAddress"
dotnet user-secrets set "Parameters:factory-address" "0xDeployedFactoryAddress"
```

Then run the whole distributed application:

```bash
cd Aspire-DEX/AspireDEX.AppHost
dotnet run
```

The Aspire dashboard opens with links to the web frontend, the API service (OpenAPI at
`/openapi` in Development), and the Redis container.

⚠️ Never use a mainnet account holding real funds for local development or demos — use a
throwaway testnet account.

## API surface

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/pools` | List every pool with live reserves, fee and circuit-breaker status |
| GET | `/api/pools/{pairAddress}` | Single pool snapshot |
| GET | `/api/pools/{pairAddress}/events?fromBlock=` | Swap events since a block |
| POST | `/api/pools` | Deploy a new pool via `Factory.createPair` |
| GET | `/api/swap/quote?amountIn=&path=&path=` | `Router.quoteExactInput` for a token path |
| POST | `/api/swap` | Execute `swapExactTokensForTokens` |
| POST | `/api/liquidity/add` | Transfer both tokens to an existing pool and mint LP tokens |
| POST | `/api/liquidity/remove` | Transfer LP tokens back to the pool and burn them |

`Router` has no `addLiquidity`/`removeLiquidity`/`getAmountsOut` of its own (see the security
note above the fold) — liquidity endpoints talk to `Pair` directly, which means the add/remove
flow is a few sequential transactions rather than one atomic call. See
`AspireDEX.Blockchain/Services/DexBlockchainService.cs` for the full explanation and the
front-running caveat that comes with that.

Token amounts cross the wire as decimal strings (wei), never as native numeric types, to avoid
precision loss on large integers.

## Roadmap

- [ ] Wallet-based transaction signing (MetaMask / WalletConnect) so users sign their own
      transactions instead of a shared operator account
- [ ] C# integration layer + API/UI for the lending protocol (`LendingPool`, `RiskEngine`, etc.)
- [x] Hardhat test suite for the AMM contracts (`Web3/test/`) — lending contracts still need one, and `DexBlockchainService` still needs xUnit tests
- [ ] `scripts/deploy.ts` to deploy Factory/Router (and eventually the lending contracts) to Sepolia
- [ ] Contracts deployed and verified on a public testnet (Sepolia), with addresses published here
- [ ] CI pipeline (build + contract tests) via GitHub Actions
- [ ] Token/pool metadata registry so the UI can resolve symbols instead of raw addresses

## License

See [LICENSE](LICENSE).
