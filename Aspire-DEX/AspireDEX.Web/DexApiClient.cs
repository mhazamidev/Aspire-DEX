namespace Aspire_DEX.Web;

/// <summary>
/// Typed HTTP client the Blazor UI uses to talk to AspireDEX.ApiService.
/// All token amounts are exchanged as decimal strings (wei) to avoid precision
/// loss — see the matching comment in ApiService/Program.cs.
///
/// Note: this Router has no addLiquidity/removeLiquidity/getAmountsOut of its own (unlike a
/// classic Uniswap V2 Router) — pools are created explicitly, quotes come from
/// quoteExactInput/quoteExactOutput, and liquidity is provisioned directly against Pair.
/// </summary>
public class DexApiClient(HttpClient httpClient)
{
    public async Task<List<PoolDto>> GetPoolsAsync(CancellationToken cancellationToken = default)
    {
        var pools = await httpClient.GetFromJsonAsync<List<PoolDto>>("/api/pools", cancellationToken);
        return pools ?? [];
    }

    public async Task<PoolDto?> GetPoolAsync(string pairAddress, CancellationToken cancellationToken = default)
        => await httpClient.GetFromJsonAsync<PoolDto>($"/api/pools/{pairAddress}", cancellationToken);

    public async Task<TransactionResult> CreatePoolAsync(CreatePoolRequestDto request, CancellationToken cancellationToken = default)
    {
        var response = await httpClient.PostAsJsonAsync("/api/pools", request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<TransactionResult>(cancellationToken))!;
    }

    public async Task<List<string>> GetSwapQuoteAsync(string amountIn, string[] path, CancellationToken cancellationToken = default)
    {
        var query = string.Join("&", path.Select(p => $"path={Uri.EscapeDataString(p)}"));
        var url = $"/api/swap/quote?amountIn={Uri.EscapeDataString(amountIn)}&{query}";

        var result = await httpClient.GetFromJsonAsync<List<string>>(url, cancellationToken);
        return result ?? [];
    }

    public async Task<TransactionResult> ExecuteSwapAsync(SwapRequestDto request, CancellationToken cancellationToken = default)
    {
        var response = await httpClient.PostAsJsonAsync("/api/swap", request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<TransactionResult>(cancellationToken))!;
    }

    public async Task<AddLiquidityResult> AddLiquidityAsync(AddLiquidityRequestDto request, CancellationToken cancellationToken = default)
    {
        var response = await httpClient.PostAsJsonAsync("/api/liquidity/add", request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<AddLiquidityResult>(cancellationToken))!;
    }

    public async Task<RemoveLiquidityResult> RemoveLiquidityAsync(RemoveLiquidityRequestDto request, CancellationToken cancellationToken = default)
    {
        var response = await httpClient.PostAsJsonAsync("/api/liquidity/remove", request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<RemoveLiquidityResult>(cancellationToken))!;
    }
}

public record PoolDto(string PairAddress, string Token0, string Token1, string LpTokenSymbol,
    string Reserve0, string Reserve1, string TotalSupply,
    int BaseFeeBps, int VolatilityFeeBps, string FeeDenominator, bool CircuitBreakerTripped);

public record TransactionResult(string TransactionHash);

public record AddLiquidityResult(string TransferATransactionHash, string TransferBTransactionHash, string MintTransactionHash, string LiquidityMinted);

public record RemoveLiquidityResult(string TransferTransactionHash, string BurnTransactionHash);

public record CreatePoolRequestDto(string TokenA, string TokenB, ushort BaseFeeBps, string FeeTo, ushort ProtocolFeeBps);

public record SwapRequestDto(string AmountIn, string AmountOutMin, string[] Path, string To, long Deadline);

public record AddLiquidityRequestDto(string TokenA, string TokenB, string AmountADesired, string AmountBDesired, string To);

public record RemoveLiquidityRequestDto(string PairAddress, string Liquidity, string To);
