using AspireDEX.Blockchain.Contracts.Pair;
using AspireDEX.Blockchain.Contracts.Pair.ContractDefinition;
using AspireDEX.Blockchain.Contracts.Router;
using AspireDEX.Blockchain.Contracts.Router.ContractDefinition;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Nethereum.RPC.Eth.DTOs;
using Nethereum.Signer;
using Nethereum.Web3;
using Nethereum.Web3.Accounts;
using System.Numerics;

namespace Aspire_DEX.Blockchain.Services;

public class DexBlockchainService(IConfiguration config, ILogger<DexBlockchainService> logger)
{
    private readonly Web3 _web3 = CreateWeb3(config);
    private readonly string _routerAddress = config["Contracts:Router"]!;
    private readonly string _factoryAddress = config["Contracts:Factory"]!;

    private static Web3 CreateWeb3(IConfiguration config)
    {
        var rpcUrl = config["Blockchain:RpcUrl"]!;
        var privateKey = config["Blockchain:PrivateKey"]!; // use Secret Manager in dev
        var account = new Account(new EthECKey(privateKey), config.GetValue<int>("Blockchain:ChainId"));
        return new Web3(account, rpcUrl);
    }

    // ── Read ───────────────────────────────────────────────────────────────

    public async Task<GetReservesOutputDTO> GetReservesAsync(string pairAddress)
    {
        var service = new PairService(_web3, pairAddress);
        return await service.GetReservesQueryAsync();
    }

    public async Task<List<BigInteger>> GetAmountsOutAsync(BigInteger amountIn, List<string> path)
    {
        var service = new RouterService(_web3, _routerAddress);
        return await service.GetAmountsOutQueryAsync(amountIn, path);
    }

    // ── Write ──────────────────────────────────────────────────────────────

    public async Task<string> SwapExactTokensAsync(
        BigInteger amountIn,
        BigInteger amountOutMin,
        List<string> path,
        string to,
        BigInteger deadline)
    {
        var service = new RouterService(_web3, _routerAddress);
        var function = new SwapExactTokensForTokensFunction
        {
            AmountIn     = amountIn,
            AmountOutMin = amountOutMin,
            Path         = path,
            To           = to,
            Deadline     = deadline
        };

        var gas = await service.ContractHandler.EstimateGasAsync(function);
        var receipt = await service.SwapExactTokensForTokensRequestAndWaitForReceiptAsync(function);

        logger.LogInformation("Swap tx: {Hash} | Gas used: {Gas}", receipt.TransactionHash, receipt.GasUsed);
        return receipt.TransactionHash;
    }

    public async Task<string> AddLiquidityAsync(
        string tokenA, string tokenB,
        BigInteger amountADesired, BigInteger amountBDesired,
        BigInteger amountAMin, BigInteger amountBMin,
        string to, BigInteger deadline)
    {
        var service = new RouterService(_web3, _routerAddress);
        var receipt = await service.AddLiquidityRequestAndWaitForReceiptAsync(
            tokenA, tokenB,
            amountADesired, amountBDesired,
            amountAMin, amountBMin,
            to, deadline
        );
        return receipt.TransactionHash;
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
