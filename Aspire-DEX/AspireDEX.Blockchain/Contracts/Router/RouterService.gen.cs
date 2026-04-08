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
        public static Task<TransactionReceipt> DeployContractAndWaitForReceiptAsync(Nethereum.Web3.IWeb3 web3, RouterDeployment routerDeployment, CancellationTokenSource cancellationTokenSource = null)
        {
            return web3.Eth.GetContractDeploymentHandler<RouterDeployment>().SendRequestAndWaitForReceiptAsync(routerDeployment, cancellationTokenSource);
        }

        public static Task<string> DeployContractAsync(Nethereum.Web3.IWeb3 web3, RouterDeployment routerDeployment)
        {
            return web3.Eth.GetContractDeploymentHandler<RouterDeployment>().SendRequestAsync(routerDeployment);
        }

        public static async Task<RouterService> DeployContractAndGetServiceAsync(Nethereum.Web3.IWeb3 web3, RouterDeployment routerDeployment, CancellationTokenSource cancellationTokenSource = null)
        {
            var receipt = await DeployContractAndWaitForReceiptAsync(web3, routerDeployment, cancellationTokenSource);
            return new RouterService(web3, receipt.ContractAddress);
        }

        public RouterService(Nethereum.Web3.IWeb3 web3, string contractAddress) : base(web3, contractAddress)
        {
        }

    }


    public partial class RouterServiceBase: ContractWeb3ServiceBase
    {

        public RouterServiceBase(Nethereum.Web3.IWeb3 web3, string contractAddress) : base(web3, contractAddress)
        {
        }

        public virtual Task<string> AddLiquidityRequestAsync(AddLiquidityFunction addLiquidityFunction)
        {
             return ContractHandler.SendRequestAsync(addLiquidityFunction);
        }

        public virtual Task<TransactionReceipt> AddLiquidityRequestAndWaitForReceiptAsync(AddLiquidityFunction addLiquidityFunction, CancellationTokenSource cancellationToken = null)
        {
             return ContractHandler.SendRequestAndWaitForReceiptAsync(addLiquidityFunction, cancellationToken);
        }

        public virtual Task<string> AddLiquidityRequestAsync(string tokenA, string tokenB, BigInteger amountADesired, BigInteger amountBDesired, BigInteger amountAMin, BigInteger amountBMin, string to, BigInteger deadline)
        {
            var addLiquidityFunction = new AddLiquidityFunction();
                addLiquidityFunction.TokenA = tokenA;
                addLiquidityFunction.TokenB = tokenB;
                addLiquidityFunction.AmountADesired = amountADesired;
                addLiquidityFunction.AmountBDesired = amountBDesired;
                addLiquidityFunction.AmountAMin = amountAMin;
                addLiquidityFunction.AmountBMin = amountBMin;
                addLiquidityFunction.To = to;
                addLiquidityFunction.Deadline = deadline;
            
             return ContractHandler.SendRequestAsync(addLiquidityFunction);
        }

        public virtual Task<TransactionReceipt> AddLiquidityRequestAndWaitForReceiptAsync(string tokenA, string tokenB, BigInteger amountADesired, BigInteger amountBDesired, BigInteger amountAMin, BigInteger amountBMin, string to, BigInteger deadline, CancellationTokenSource cancellationToken = null)
        {
            var addLiquidityFunction = new AddLiquidityFunction();
                addLiquidityFunction.TokenA = tokenA;
                addLiquidityFunction.TokenB = tokenB;
                addLiquidityFunction.AmountADesired = amountADesired;
                addLiquidityFunction.AmountBDesired = amountBDesired;
                addLiquidityFunction.AmountAMin = amountAMin;
                addLiquidityFunction.AmountBMin = amountBMin;
                addLiquidityFunction.To = to;
                addLiquidityFunction.Deadline = deadline;
            
             return ContractHandler.SendRequestAndWaitForReceiptAsync(addLiquidityFunction, cancellationToken);
        }

        public Task<string> FactoryQueryAsync(FactoryFunction factoryFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<FactoryFunction, string>(factoryFunction, blockParameter);
        }

        
        public virtual Task<string> FactoryQueryAsync(BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<FactoryFunction, string>(null, blockParameter);
        }

        public Task<BigInteger> GetAmountOutQueryAsync(GetAmountOutFunction getAmountOutFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<GetAmountOutFunction, BigInteger>(getAmountOutFunction, blockParameter);
        }

        
        public virtual Task<BigInteger> GetAmountOutQueryAsync(BigInteger amountIn, BigInteger reserveIn, BigInteger reserveOut, BlockParameter blockParameter = null)
        {
            var getAmountOutFunction = new GetAmountOutFunction();
                getAmountOutFunction.AmountIn = amountIn;
                getAmountOutFunction.ReserveIn = reserveIn;
                getAmountOutFunction.ReserveOut = reserveOut;
            
            return ContractHandler.QueryAsync<GetAmountOutFunction, BigInteger>(getAmountOutFunction, blockParameter);
        }

        public Task<List<BigInteger>> GetAmountsOutQueryAsync(GetAmountsOutFunction getAmountsOutFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<GetAmountsOutFunction, List<BigInteger>>(getAmountsOutFunction, blockParameter);
        }

        
        public virtual Task<List<BigInteger>> GetAmountsOutQueryAsync(BigInteger amountIn, List<string> path, BlockParameter blockParameter = null)
        {
            var getAmountsOutFunction = new GetAmountsOutFunction();
                getAmountsOutFunction.AmountIn = amountIn;
                getAmountsOutFunction.Path = path;
            
            return ContractHandler.QueryAsync<GetAmountsOutFunction, List<BigInteger>>(getAmountsOutFunction, blockParameter);
        }

        public virtual Task<string> RemoveLiquidityRequestAsync(RemoveLiquidityFunction removeLiquidityFunction)
        {
             return ContractHandler.SendRequestAsync(removeLiquidityFunction);
        }

        public virtual Task<TransactionReceipt> RemoveLiquidityRequestAndWaitForReceiptAsync(RemoveLiquidityFunction removeLiquidityFunction, CancellationTokenSource cancellationToken = null)
        {
             return ContractHandler.SendRequestAndWaitForReceiptAsync(removeLiquidityFunction, cancellationToken);
        }

        public virtual Task<string> RemoveLiquidityRequestAsync(string tokenA, string tokenB, BigInteger liquidity, BigInteger amountAMin, BigInteger amountBMin, string to, BigInteger deadline)
        {
            var removeLiquidityFunction = new RemoveLiquidityFunction();
                removeLiquidityFunction.TokenA = tokenA;
                removeLiquidityFunction.TokenB = tokenB;
                removeLiquidityFunction.Liquidity = liquidity;
                removeLiquidityFunction.AmountAMin = amountAMin;
                removeLiquidityFunction.AmountBMin = amountBMin;
                removeLiquidityFunction.To = to;
                removeLiquidityFunction.Deadline = deadline;
            
             return ContractHandler.SendRequestAsync(removeLiquidityFunction);
        }

        public virtual Task<TransactionReceipt> RemoveLiquidityRequestAndWaitForReceiptAsync(string tokenA, string tokenB, BigInteger liquidity, BigInteger amountAMin, BigInteger amountBMin, string to, BigInteger deadline, CancellationTokenSource cancellationToken = null)
        {
            var removeLiquidityFunction = new RemoveLiquidityFunction();
                removeLiquidityFunction.TokenA = tokenA;
                removeLiquidityFunction.TokenB = tokenB;
                removeLiquidityFunction.Liquidity = liquidity;
                removeLiquidityFunction.AmountAMin = amountAMin;
                removeLiquidityFunction.AmountBMin = amountBMin;
                removeLiquidityFunction.To = to;
                removeLiquidityFunction.Deadline = deadline;
            
             return ContractHandler.SendRequestAndWaitForReceiptAsync(removeLiquidityFunction, cancellationToken);
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

        public override List<Type> GetAllFunctionTypes()
        {
            return new List<Type>
            {
                typeof(AddLiquidityFunction),
                typeof(FactoryFunction),
                typeof(GetAmountOutFunction),
                typeof(GetAmountsOutFunction),
                typeof(RemoveLiquidityFunction),
                typeof(SwapExactTokensForTokensFunction)
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

            };
        }
    }
}
