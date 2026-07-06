using Aspire_DEX.Blockchain.Services;
using System.Numerics;

var builder = WebApplication.CreateBuilder(args);

// Add service defaults & Aspire client integrations.
builder.AddServiceDefaults();

// Add services to the container.
builder.Services.AddProblemDetails();
builder.Services.AddSingleton<DexBlockchainService>();

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapGet("/", () => "AspireDEX API is running. See /openapi for the endpoint catalog.");

// ── Pools ────────────────────────────────────────────────────────────────

app.MapGet("/api/pools", async (DexBlockchainService dex) =>
{
    var pools = await dex.GetAllPoolsAsync();
    return Results.Ok(pools.Select(PoolResponse.FromPoolInfo));
})
.WithName("GetPools")
.WithSummary("Lists every liquidity pool known to the Factory, with live reserves and fee/circuit-breaker status.");

app.MapGet("/api/pools/{pairAddress}", async (string pairAddress, DexBlockchainService dex) =>
{
    var pool = await dex.GetPoolInfoAsync(pairAddress);
    return Results.Ok(PoolResponse.FromPoolInfo(pool));
})
.WithName("GetPool")
.WithSummary("Returns token addresses, reserves, LP total supply, fee and circuit-breaker status for a single pool.");

app.MapGet("/api/pools/{pairAddress}/events", async (string pairAddress, ulong fromBlock, DexBlockchainService dex) =>
{
    var events = await dex.GetSwapEventsAsync(pairAddress, fromBlock);
    var response = events.Select(e => new SwapEventResponse(
        e.Sender,
        e.To,
        e.Amount0In.ToString(),
        e.Amount1In.ToString(),
        e.Amount0Out.ToString(),
        e.Amount1Out.ToString()));

    return Results.Ok(response);
})
.WithName("GetPoolSwapEvents")
.WithSummary("Returns Swap events emitted by a pool since the given block.");

app.MapPost("/api/pools", async (CreatePoolRequest request, DexBlockchainService dex) =>
{
    var txHash = await dex.CreatePairAsync(request.TokenA, request.TokenB, request.BaseFeeBps, request.FeeTo, request.ProtocolFeeBps);
    return Results.Ok(new { transactionHash = txHash });
})
.WithName("CreatePool")
.WithSummary("Deploys a new Pair for a token pair via the Factory. baseFeeBps/protocolFeeBps are out of 10_000.");

// ── Swap ─────────────────────────────────────────────────────────────────
// Note: this Router has no getAmountsOut of a classic Uniswap V2 Router — quotes come from
// quoteExactInput/quoteExactOutput, which also apply this Router's dynamic fee.

app.MapGet("/api/swap/quote", async (string amountIn, string[] path, DexBlockchainService dex) =>
{
    if (!BigInteger.TryParse(amountIn, out var parsedAmountIn))
    {
        return Results.BadRequest(new { error = "amountIn must be an integer string denominated in the token's smallest unit (wei)." });
    }

    var amountsOut = await dex.QuoteExactInputAsync(parsedAmountIn, path.ToList());
    return Results.Ok(amountsOut.Select(a => a.ToString()));
})
.WithName("GetSwapQuote")
.WithSummary("Given an input amount and a token path, returns the expected output at each hop (Router.quoteExactInput).");

app.MapPost("/api/swap", async (SwapRequest request, DexBlockchainService dex) =>
{
    var txHash = await dex.SwapExactTokensAsync(
        BigInteger.Parse(request.AmountIn),
        BigInteger.Parse(request.AmountOutMin),
        request.Path.ToList(),
        request.To,
        request.Deadline);

    return Results.Ok(new { transactionHash = txHash });
})
.WithName("ExecuteSwap")
.WithSummary("Executes a swapExactTokensForTokens transaction on the Router and waits for the receipt.");

// ── Liquidity ────────────────────────────────────────────────────────────
// Note: this Router has no addLiquidity/removeLiquidity of its own — liquidity is provisioned
// directly against Pair (transfer tokens in, then mint/burn). See DexBlockchainService remarks
// for the atomicity/front-running caveat that comes with that.

app.MapPost("/api/liquidity/add", async (AddLiquidityRequest request, DexBlockchainService dex) =>
{
    var (transferATx, transferBTx, mintTx, liquidityMinted) = await dex.AddLiquidityAsync(
        request.TokenA, request.TokenB,
        BigInteger.Parse(request.AmountADesired), BigInteger.Parse(request.AmountBDesired),
        request.To);

    return Results.Ok(new
    {
        transferATransactionHash = transferATx,
        transferBTransactionHash = transferBTx,
        mintTransactionHash = mintTx,
        liquidityMinted = liquidityMinted.ToString()
    });
})
.WithName("AddLiquidity")
.WithSummary("Transfers both tokens to the pair and mints LP tokens to the recipient. The pool must already exist.");

app.MapPost("/api/liquidity/remove", async (RemoveLiquidityRequest request, DexBlockchainService dex) =>
{
    var (transferTx, burnTx) = await dex.RemoveLiquidityAsync(
        request.PairAddress,
        BigInteger.Parse(request.Liquidity),
        request.To);

    return Results.Ok(new { transferTransactionHash = transferTx, burnTransactionHash = burnTx });
})
.WithName("RemoveLiquidity")
.WithSummary("Transfers LP tokens back to the pair and burns them, returning the underlying tokens to the recipient.");

app.MapDefaultEndpoints();

app.Run();

// ── DTOs ──────────────────────────────────────────────────────────────────
// Token amounts cross the wire as decimal strings (wei), never as BigInteger/long/double,
// to avoid precision loss and JSON-serialization surprises for numbers that routinely
// exceed 2^53 (JS safe-integer range) or the range .NET's System.Text.Json handles
// natively for System.Numerics.BigInteger.

record PoolResponse(string PairAddress, string Token0, string Token1, string LpTokenSymbol,
    string Reserve0, string Reserve1, string TotalSupply,
    int BaseFeeBps, int VolatilityFeeBps, string FeeDenominator, bool CircuitBreakerTripped)
{
    public static PoolResponse FromPoolInfo(PoolInfo info) => new(
        info.PairAddress, info.Token0, info.Token1, info.LpTokenSymbol,
        info.Reserve0.ToString(), info.Reserve1.ToString(), info.TotalSupply.ToString(),
        info.BaseFeeBps, info.VolatilityFeeBps, info.FeeDenominator.ToString(), info.CircuitBreakerTripped);
}

record SwapEventResponse(string Sender, string To, string Amount0In, string Amount1In, string Amount0Out, string Amount1Out);

record CreatePoolRequest(string TokenA, string TokenB, ushort BaseFeeBps, string FeeTo, ushort ProtocolFeeBps);

record SwapRequest(string AmountIn, string AmountOutMin, string[] Path, string To, long Deadline);

record AddLiquidityRequest(
    string TokenA, string TokenB,
    string AmountADesired, string AmountBDesired,
    string To);

record RemoveLiquidityRequest(string PairAddress, string Liquidity, string To);
