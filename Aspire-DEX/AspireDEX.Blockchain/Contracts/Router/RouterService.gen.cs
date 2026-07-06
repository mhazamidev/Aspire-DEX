using System;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Numerics;
using Nethereum.Hex.HexTypes;
using Nethereum.ABI.FunctionEncoding.Attributes;
using Nethereum.Web3;
using Nethereum.RPC.Eth.DTOs;
using Nethereum.Contracts.CQS;
using Nethereum.Contracts.ContractHandlers;
using Nethereum.Contracts;
using System.Threading;
using AspireDEX.Blockchain.Contracts.Router.ContractDefinition;

namespace AspireDEX.Blockchain.Contracts.Router
{
    public partial class RouterService: RouterServiceBase
    {
        public static Task<TransactionReceipt> DeployContractAndWaitForReceiptAsync(IWeb3 web3, RouterDeployment routerDeployment, CancellationTokenSource cancellationTokenSource = null)
        {
            return web3.Eth.GetContractDeploymentHandler<RouterDeployment>().SendRequestAndWaitForReceiptAsync(routerDeployment, cancellationTokenSource);
        }

        public static Task<string> DeployContractAsync(IWeb3 web3, RouterDeployment routerDeployment)
        {
            return web3.Eth.GetContractDeploymentHandler<RouterDeployment>().SendRequestAsync(routerDeployment);
        }

        public static async Task<RouterService> DeployContractAndGetServiceAsync(IWeb3 web3, RouterDeployment routerDeployment, CancellationTokenSource cancellationTokenSource = null)
        {
            var receipt = await DeployContractAndWaitForReceiptAsync(web3, routerDeployment, cancellationTokenSource);
            return new RouterService(web3, receipt.ContractAddress);
        }

        public RouterService(IWeb3 web3, string contractAddress) : base(web3, contractAddress)
        {
        }

    }


    public partial class RouterServiceBase : ContractWeb3ServiceBase
    {

        public RouterServiceBase(IWeb3 web3, string contractAddress) : base(web3, contractAddress)
        {
        }

        public Task<string> FactoryQueryAsync(FactoryFunction factoryFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<FactoryFunction, string>(factoryFunction, blockParameter);
        }

        public virtual Task<string> FactoryQueryAsync(BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<FactoryFunction, string>(null, blockParameter);
        }

        public Task<string> OracleQueryAsync(OracleFunction oracleFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<OracleFunction, string>(oracleFunction, blockParameter);
        }

        public virtual Task<string> OracleQueryAsync(BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<OracleFunction, string>(null, blockParameter);
        }

        public virtual Task<List<BigInteger>> QuoteExactInputQueryAsync(QuoteExactInputFunction quoteExactInputFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<QuoteExactInputFunction, List<BigInteger>>(quoteExactInputFunction, blockParameter);
        }

        public virtual Task<List<BigInteger>> QuoteExactInputQueryAsync(BigInteger amountIn, List<string> path, BlockParameter blockParameter = null)
        {
            var quoteExactInputFunction = new QuoteExactInputFunction();
            quoteExactInputFunction.AmountIn = amountIn;
            quoteExactInputFunction.Path = path;

            return ContractHandler.QueryAsync<QuoteExactInputFunction, List<BigInteger>>(quoteExactInputFunction, blockParameter);
        }

        public virtual Task<List<BigInteger>> QuoteExactOutputQueryAsync(QuoteExactOutputFunction quoteExactOutputFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<QuoteExactOutputFunction, List<BigInteger>>(quoteExactOutputFunction, blockParameter);
        }

        public virtual Task<List<BigInteger>> QuoteExactOutputQueryAsync(BigInteger amountOut, List<string> path, BlockParameter blockParameter = null)
        {
            var quoteExactOutputFunction = new QuoteExactOutputFunction();
            quoteExactOutputFunction.AmountOut = amountOut;
            quoteExactOutputFunction.Path = path;

            return ContractHandler.QueryAsync<QuoteExactOutputFunction, List<BigInteger>>(quoteExactOutputFunction, blockParameter);
        }

        public virtual Task<string> SwapExactTokensForTokensRequestAsync(SwapExactTokensForTokensFunction swapExactTokensForTokensFunction)
        {
            return ContractHandler.SendRequestAsync(swapExactTokensForTokensFunction);
        }

        public virtual Task<TransactionReceipt> SwapExactTokensForTokensRequestAndWaitForReceiptAsync(SwapExactTokensForTokensFunction swapExactTokensForTokensFunction, CancellationTokenSource cancellationToken = null)
        {
            return ContractHandler.SendRequestAndWaitForReceiptAsync(swapExactTokensForTokensFunction, cancellationToken);
        }

        public virtual Task<string> SwapExactTokensForTokensRequestAsync(BigInteger amountIn, BigInteger amountOutMin, List<string> path, string to, BigInteger deadline)
        {
            var swapExactTokensForTokensFunction = new SwapExactTokensForTokensFunction();
            swapExactTokensForTokensFunction.AmountIn = amountIn;
            swapExactTokensForTokensFunction.AmountOutMin = amountOutMin;
            swapExactTokensForTokensFunction.Path = path;
            swapExactTokensForTokensFunction.To = to;
            swapExactTokensForTokensFunction.Deadline = deadline;

            return ContractHandler.SendRequestAsync(swapExactTokensForTokensFunction);
        }

        public virtual Task<TransactionReceipt> SwapExactTokensForTokensRequestAndWaitForReceiptAsync(BigInteger amountIn, BigInteger amountOutMin, List<string> path, string to, BigInteger deadline, CancellationTokenSource cancellationToken = null)
        {
            var swapExactTokensForTokensFunction = new SwapExactTokensForTokensFunction();
            swapExactTokensForTokensFunction.AmountIn = amountIn;
            swapExactTokensForTokensFunction.AmountOutMin = amountOutMin;
            swapExactTokensForTokensFunction.Path = path;
            swapExactTokensForTokensFunction.To = to;
            swapExactTokensForTokensFunction.Deadline = deadline;

            return ContractHandler.SendRequestAndWaitForReceiptAsync(swapExactTokensForTokensFunction, cancellationToken);
        }

        public virtual Task<string> SwapTokensForExactTokensRequestAsync(SwapTokensForExactTokensFunction swapTokensForExactTokensFunction)
        {
            return ContractHandler.SendRequestAsync(swapTokensForExactTokensFunction);
        }

        public virtual Task<TransactionReceipt> SwapTokensForExactTokensRequestAndWaitForReceiptAsync(SwapTokensForExactTokensFunction swapTokensForExactTokensFunction, CancellationTokenSource cancellationToken = null)
        {
            return ContractHandler.SendRequestAndWaitForReceiptAsync(swapTokensForExactTokensFunction, cancellationToken);
        }

        public virtual Task<string> SwapTokensForExactTokensRequestAsync(BigInteger amountOut, BigInteger amountInMax, List<string> path, string to, BigInteger deadline)
        {
            var swapTokensForExactTokensFunction = new SwapTokensForExactTokensFunction();
            swapTokensForExactTokensFunction.AmountOut = amountOut;
            swapTokensForExactTokensFunction.AmountInMax = amountInMax;
            swapTokensForExactTokensFunction.Path = path;
            swapTokensForExactTokensFunction.To = to;
            swapTokensForExactTokensFunction.Deadline = deadline;

            return ContractHandler.SendRequestAsync(swapTokensForExactTokensFunction);
        }

        public virtual Task<TransactionReceipt> SwapTokensForExactTokensRequestAndWaitForReceiptAsync(BigInteger amountOut, BigInteger amountInMax, List<string> path, string to, BigInteger deadline, CancellationTokenSource cancellationToken = null)
        {
            var swapTokensForExactTokensFunction = new SwapTokensForExactTokensFunction();
            swapTokensForExactTokensFunction.AmountOut = amountOut;
            swapTokensForExactTokensFunction.AmountInMax = amountInMax;
            swapTokensForExactTokensFunction.Path = path;
            swapTokensForExactTokensFunction.To = to;
            swapTokensForExactTokensFunction.Deadline = deadline;

            return ContractHandler.SendRequestAndWaitForReceiptAsync(swapTokensForExactTokensFunction, cancellationToken);
        }

        public override List<Type> GetAllFunctionTypes()
        {
            return new List<Type>
            {
                typeof(FactoryFunction),
                typeof(OracleFunction),
                typeof(QuoteExactInputFunction),
                typeof(QuoteExactOutputFunction),
                typeof(SwapExactTokensForTokensFunction),
                typeof(SwapTokensForExactTokensFunction)
            };
        }

        public override List<Type> GetAllEventTypes()
        {
            return new List<Type>
            {

            };
        }

        public override List<Type> GetAllErrorTypes()
        {
            return new List<Type>
            {
                typeof(ExpiredError),
                typeof(InsufficientOutputAmountError),
                typeof(ExcessiveInputAmountError),
                typeof(OraclePriceDeviationError),
                typeof(InvalidPathError),
                typeof(PairDoesNotExistError),
                typeof(CircuitBreakerActiveError)
            };
        }
    }
}
