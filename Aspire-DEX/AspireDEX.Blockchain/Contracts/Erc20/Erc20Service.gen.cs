using System.Numerics;
using Nethereum.Contracts.ContractHandlers;
using Nethereum.RPC.Eth.DTOs;
using Nethereum.Web3;
using AspireDEX.Blockchain.Contracts.Erc20.ContractDefinition;

namespace AspireDEX.Blockchain.Contracts.Erc20
{
    /// <summary>Thin wrapper over any standard ERC20 token — not tied to a specific deployment.</summary>
    public class Erc20Service : ContractWeb3ServiceBase
    {
        public Erc20Service(IWeb3 web3, string contractAddress) : base(web3, contractAddress)
        {
        }

        public Task<BigInteger> BalanceOfQueryAsync(string account, BlockParameter blockParameter = null)
        {
            var function = new BalanceOfFunction { Account = account };
            return ContractHandler.QueryAsync<BalanceOfFunction, BigInteger>(function, blockParameter);
        }

        public Task<byte> DecimalsQueryAsync(BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<DecimalsFunction, byte>(null, blockParameter);
        }

        public Task<string> SymbolQueryAsync(BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<SymbolFunction, string>(null, blockParameter);
        }

        public Task<TransactionReceipt> ApproveRequestAndWaitForReceiptAsync(string spender, BigInteger amount, CancellationTokenSource cancellationToken = null)
        {
            var function = new ApproveFunction { Spender = spender, Amount = amount };
            return ContractHandler.SendRequestAndWaitForReceiptAsync(function, cancellationToken);
        }

        public Task<TransactionReceipt> TransferRequestAndWaitForReceiptAsync(string to, BigInteger amount, CancellationTokenSource cancellationToken = null)
        {
            var function = new TransferFunction { To = to, Amount = amount };
            return ContractHandler.SendRequestAndWaitForReceiptAsync(function, cancellationToken);
        }

        public override List<Type> GetAllFunctionTypes()
        {
            return new List<Type>
            {
                typeof(BalanceOfFunction),
                typeof(DecimalsFunction),
                typeof(SymbolFunction),
                typeof(ApproveFunction),
                typeof(TransferFunction)
            };
        }

        public override List<Type> GetAllEventTypes()
        {
            // Intentionally minimal: this wrapper only covers the handful of standard ERC20
            // functions AddLiquidity/RemoveLiquidity actually need (see DexBlockchainService).
            // It doesn't declare Transfer/Approval events or the ERC20 custom errors, since
            // nothing here decodes them — add them here first if a caller ever needs to.
            return new List<Type>();
        }

        public override List<Type> GetAllErrorTypes()
        {
            return new List<Type>();
        }
    }
}

