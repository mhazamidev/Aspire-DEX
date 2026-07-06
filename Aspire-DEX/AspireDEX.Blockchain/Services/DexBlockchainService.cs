using AspireDEX.Blockchain.Contracts.Erc20;
using AspireDEX.Blockchain.Contracts.Factory;
using AspireDEX.Blockchain.Contracts.Pair;
using AspireDEX.Blockchain.Contracts.Pair.ContractDefinition;
using AspireDEX.Blockchain.Contracts.Router;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Nethereum.Contracts;
using Nethereum.RPC.Eth.DTOs;
using Nethereum.Signer;
using Nethereum.Web3;
using Nethereum.Web3.Accounts;
using System;
using System.Numerics;

namespace Aspire_DEX.Blockchain.Services;

/// <summary>
/// Full snapshot of a liquidity pool: tokens, current reserves, LP total supply, the pool's
/// dynamic fee (baseFee + volatilityFee, in bps out of FEE_DENOMINATOR) and whether its
/// circuit breaker has tripped. Assembled from several on-chain reads so the API/UI layer
/// only needs a single call.
/// </summary>
public record PoolInfo(
    string PairAddress,
    string Token0,
    string Token1,
    string LpTokenSymbol,
    BigInteger Reserve0,
    BigInteger Reserve1,
    BigInteger TotalSupply,
    ushort BaseFeeBps,
    ushort VolatilityFeeBps,
    BigInteger FeeDenominator,
    bool CircuitBreakerTripped);

/// <summary>
/// Talks to the AMM side of the AspireDEX protocol (Factory / Pair / Router — see Web3/contracts).
///
/// Important shape of this Router: unlike a classic Uniswap V2 Router, it has no addLiquidity/
/// removeLiquidity/getAmountsOut of its own. It only quotes (quoteExactInput/quoteExactOutput)
/// and executes swaps (swapExactTokensForTokens/swapTokensForExactTokens), with an oracle-
/// deviation check and a per-pair circuit breaker on top of the constant-product core.
///
/// Liquidity is provisioned directly against Pair, mirroring Uniswap V2's core contract:
///   Add:    transfer both tokens to the pair address, then call Pair.mint(to)
///   Remove: transfer the LP tokens to the pair address itself, then call Pair.burn(to)
/// A pool must exist first — the Factory creates it via createPair(tokenA, tokenB, baseFee,
/// feeTo, protocolFeeBps); it isn't created implicitly on first deposit.
/// </summary>
public class DexBlockchainService(IConfiguration config, ILogger<DexBlockchainService> logger)
{
    private readonly Web3 _web3 = CreateWeb3(config);
    private readonly string _routerAddress = config["Contracts:Router"]!;
    private readonly string _factoryAddress = config["Contracts:Factory"]!;

    private static Web3 CreateWeb3(IConfiguration config)
    {
        var rpcUrl = config["Blockchain:RpcUrl"]!;
        var privateKey = config["Blockchain:PrivateKey"]!; // set via Aspire user-secrets, see AppHost.cs
        var chainId = int.TryParse(config.GetSection("Blockchain:ChainId").Value, out var id) ? id : throw new InvalidOperationException("Invalid chain ID");
        var account = new Account(new EthECKey(privateKey), chainId);
        return new Web3(account, rpcUrl);
    }

    // ── Read ───────────────────────────────────────────────────────────────

    public async Task<GetReservesOutputDTO> GetReservesAsync(string pairAddress)
    {
        var service = new PairService(_web3, pairAddress);
        return await service.GetReservesQueryAsync();
    }

    /// <summary>Quote for swapping an exact input amount along a token path (Router.quoteExactInput).</summary>
    public async Task<List<BigInteger>> QuoteExactInputAsync(BigInteger amountIn, List<string> path)
    {
        var service = new RouterService(_web3, _routerAddress);
        return await service.QuoteExactInputQueryAsync(amountIn, path);
    }

    /// <summary>Quote for receiving an exact output amount along a token path (Router.quoteExactOutput).</summary>
    public async Task<List<BigInteger>> QuoteExactOutputAsync(BigInteger amountOut, List<string> path)
    {
        var service = new RouterService(_web3, _routerAddress);
        return await service.QuoteExactOutputQueryAsync(amountOut, path);
    }

    /// <summary>Resolves the Pair contract address for a token pair, or null if no pool exists yet.</summary>
    public async Task<string?> GetPairAddressAsync(string tokenA, string tokenB)
    {
        var factory = new FactoryService(_web3, _factoryAddress);
        var pairAddress = await factory.GetPairQueryAsync(tokenA, tokenB);
        return pairAddress == "0x0000000000000000000000000000000000000000" ? null : pairAddress;
    }

    /// <summary>Returns the on-chain address of every pool created by the Factory.</summary>
    public async Task<List<string>> GetAllPairAddressesAsync()
    {
        var factory = new FactoryService(_web3, _factoryAddress);
        var count = await factory.AllPairsLengthQueryAsync();

        var addresses = new List<string>();
        for (var i = BigInteger.Zero; i < count; i++)
        {
            addresses.Add(await factory.AllPairsQueryAsync(i));
        }
        return addresses;
    }

    /// <summary>
    /// Reads token addresses, symbols, reserves, LP total supply, current fee and circuit-breaker
    /// status for a single pool in one call, so the UI can render a pool card without chaining
    /// requests itself.
    /// </summary>
    public async Task<PoolInfo> GetPoolInfoAsync(string pairAddress)
    {
        var pair = new PairService(_web3, pairAddress);

        var token0 = await pair.Token0QueryAsync();
        var token1 = await pair.Token1QueryAsync();
        var lpSymbol = await pair.SymbolQueryAsync();
        var reserves = await pair.GetReservesQueryAsync();
        var totalSupply = await pair.TotalSupplyQueryAsync();
        var baseFee = await pair.BaseFeeQueryAsync();
        var volatilityFee = await pair.VolatilityFeeQueryAsync();
        var feeDenominator = await pair.FeeDenominatorQueryAsync();
        var circuitBreakerTripped = await pair.CircuitBreakerTrippedQueryAsync();

        return new PoolInfo(
            PairAddress: pairAddress,
            Token0: token0,
            Token1: token1,
            LpTokenSymbol: lpSymbol,
            Reserve0: reserves.Reserve0,
            Reserve1: reserves.Reserve1,
            TotalSupply: totalSupply,
            BaseFeeBps: baseFee,
            VolatilityFeeBps: volatilityFee,
            FeeDenominator: feeDenominator,
            CircuitBreakerTripped: circuitBreakerTripped);
    }

    /// <summary>Convenience method returning full pool snapshots for every pool in the Factory.</summary>
    public async Task<List<PoolInfo>> GetAllPoolsAsync()
    {
        var addresses = await GetAllPairAddressesAsync();
        var pools = new List<PoolInfo>();
        foreach (var address in addresses)
        {
            pools.Add(await GetPoolInfoAsync(address));
        }
        return pools;
    }

    // ── Write: swaps ─────────────────────────────────────────────────────────

    public async Task<string> SwapExactTokensAsync(
        BigInteger amountIn,
        BigInteger amountOutMin,
        List<string> path,
        string to,
        BigInteger deadline)
    {
        var service = new RouterService(_web3, _routerAddress);
        var receipt = await service.SwapExactTokensForTokensRequestAndWaitForReceiptAsync(
            amountIn, amountOutMin, path, to, deadline);

        logger.LogInformation("Swap tx: {Hash} | Gas used: {Gas}", receipt.TransactionHash, receipt.GasUsed);
        return receipt.TransactionHash;
    }

    public async Task<string> SwapTokensForExactTokensAsync(
        BigInteger amountOut,
        BigInteger amountInMax,
        List<string> path,
        string to,
        BigInteger deadline)
    {
        var service = new RouterService(_web3, _routerAddress);
        var receipt = await service.SwapTokensForExactTokensRequestAndWaitForReceiptAsync(
            amountOut, amountInMax, path, to, deadline);

        logger.LogInformation("Swap tx: {Hash} | Gas used: {Gas}", receipt.TransactionHash, receipt.GasUsed);
        return receipt.TransactionHash;
    }

    // ── Write: pool creation ──────────────────────────────────────────────────

    /// <summary>
    /// Deploys a new Pair for (tokenA, tokenB) via the Factory. baseFee/protocolFeeBps are in
    /// basis points out of Pair.FEE_DENOMINATOR (10_000) — e.g. baseFee: 30 = 0.30%. Pass
    /// feeTo = "0x0000000000000000000000000000000000000000" and protocolFeeBps: 0 to disable
    /// the protocol fee cut.
    /// </summary>
    public async Task<string> CreatePairAsync(string tokenA, string tokenB, ushort baseFee, string feeTo, ushort protocolFeeBps)
    {
        var factory = new FactoryService(_web3, _factoryAddress);
        var receipt = await factory.CreatePairRequestAndWaitForReceiptAsync(tokenA, tokenB, baseFee, feeTo, protocolFeeBps);
        return receipt.TransactionHash;
    }

    // ── Write: liquidity (direct against Pair — see class remarks) ───────────

    /// <summary>
    /// Adds liquidity to an existing pool: transfers amountA/amountB of the underlying ERC20
    /// tokens to the pair address, then calls Pair.mint(to). The pool must already exist
    /// (see <see cref="CreatePairAsync"/>) — this does not create one implicitly.
    /// ⚠️ Unlike a single atomic Router.addLiquidity call, this is three sequential
    /// transactions (transfer, transfer, mint) with no slippage/minimum-amount protection —
    /// each step can be seen (and in principle front-run) independently on a public mempool.
    /// Acceptable for an operator-signed demo/testnet flow; a production deployment should add
    /// an atomic addLiquidity wrapper on Router before handling untrusted user funds.
    /// </summary>
    public async Task<(string TransferATxHash, string TransferBTxHash, string MintTxHash, BigInteger LiquidityMinted)> AddLiquidityAsync(
        string tokenA, string tokenB,
        BigInteger amountADesired, BigInteger amountBDesired,
        string to)
    {
        var pairAddress = await GetPairAddressAsync(tokenA, tokenB)
            ?? throw new InvalidOperationException($"No pool exists for {tokenA}/{tokenB} yet — call CreatePairAsync first.");

        var tokenAService = new Erc20Service(_web3, tokenA);
        var tokenBService = new Erc20Service(_web3, tokenB);

        var transferAReceipt = await tokenAService.TransferRequestAndWaitForReceiptAsync(pairAddress, amountADesired);
        var transferBReceipt = await tokenBService.TransferRequestAndWaitForReceiptAsync(pairAddress, amountBDesired);

        var pair = new PairService(_web3, pairAddress);
        var mintReceipt = await pair.MintRequestAndWaitForReceiptAsync(to);

        // Pair.mint returns `liquidity` but Nethereum's SendRequestAndWaitForReceiptAsync only
        // gives us the receipt, not the decoded return value (that requires a local call/simulate
        // for state-changing functions). The Mint event itself only carries amount0/amount1
        // deposited, not the liquidity minted — so read it from the ERC20 Transfer(0x0 -> to)
        // event that OpenZeppelin's _mint always emits alongside it.
        const string zeroAddress = "0x0000000000000000000000000000000000000000";
        var liquidityMinted = mintReceipt.DecodeAllEvents<TransferEventDTO>()
            .FirstOrDefault(e => e.Event.From.Equals(zeroAddress, StringComparison.OrdinalIgnoreCase))
            ?.Event.Value ?? BigInteger.Zero;

        logger.LogInformation("AddLiquidity: transferA {A} | transferB {B} | mint {Mint}",
            transferAReceipt.TransactionHash, transferBReceipt.TransactionHash, mintReceipt.TransactionHash);

        return (transferAReceipt.TransactionHash, transferBReceipt.TransactionHash, mintReceipt.TransactionHash, liquidityMinted);
    }

    /// <summary>
    /// Removes liquidity from a pool: transfers `liquidity` LP tokens to the pair address itself
    /// (Pair is its own ERC20), then calls Pair.burn(to) to redeem the underlying tokens.
    /// </summary>
    public async Task<(string TransferTxHash, string BurnTxHash)> RemoveLiquidityAsync(
        string pairAddress,
        BigInteger liquidity,
        string to)
    {
        var pair = new PairService(_web3, pairAddress);

        var transferReceipt = await pair.TransferRequestAndWaitForReceiptAsync(pairAddress, liquidity);
        var burnReceipt = await pair.BurnRequestAndWaitForReceiptAsync(to);

        logger.LogInformation("RemoveLiquidity: transfer {Transfer} | burn {Burn}",
            transferReceipt.TransactionHash, burnReceipt.TransactionHash);

        return (transferReceipt.TransactionHash, burnReceipt.TransactionHash);
    }

    // ── Events ─────────────────────────────────────────────────────────────

    public async Task<List<SwapEventDTO>> GetSwapEventsAsync(string pairAddress, ulong fromBlock)
    {
        var service = new PairService(_web3, pairAddress);
        var events = await service.GetSwapEventsAsync(
            new BlockParameter(fromBlock),
            BlockParameter.CreateLatest()
        );
        return events.Select(e => e.Event).ToList();
    }
}
