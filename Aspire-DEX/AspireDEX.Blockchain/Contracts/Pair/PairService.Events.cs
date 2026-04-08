using AspireDEX.Blockchain.Contracts.Pair.ContractDefinition;
using Nethereum.Contracts;
using Nethereum.RPC.Eth.DTOs;

namespace AspireDEX.Blockchain.Contracts.Pair;

public partial class PairService
{
    public Task<List<EventLog<SwapEventDTO>>> GetSwapEventsAsync(
        BlockParameter fromBlock,
        BlockParameter toBlock)
    {
        var handler = Web3.Eth.GetEvent<SwapEventDTO>(ContractHandler.ContractAddress);
        var filter = handler.CreateFilterInput(fromBlock, toBlock);
        return handler.GetAllChangesAsync(filter);
    }

    public Task<List<EventLog<MintEventDTO>>> GetMintEventsAsync(
        BlockParameter fromBlock,
        BlockParameter toBlock)
    {
        var handler = Web3.Eth.GetEvent<MintEventDTO>(ContractHandler.ContractAddress);
        var filter = handler.CreateFilterInput(fromBlock, toBlock);
        return handler.GetAllChangesAsync(filter);
    }

    public Task<List<EventLog<BurnEventDTO>>> GetBurnEventsAsync(
        BlockParameter fromBlock,
        BlockParameter toBlock)
    {
        var handler = Web3.Eth.GetEvent<BurnEventDTO>(ContractHandler.ContractAddress);
        var filter = handler.CreateFilterInput(fromBlock, toBlock);
        return handler.GetAllChangesAsync(filter);
    }

    public Task<List<EventLog<SyncEventDTO>>> GetSyncEventsAsync(
        BlockParameter fromBlock,
        BlockParameter toBlock)
    {
        var handler = Web3.Eth.GetEvent<SyncEventDTO>(ContractHandler.ContractAddress);
        var filter = handler.CreateFilterInput(fromBlock, toBlock);
        return handler.GetAllChangesAsync(filter);
    }
}