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
using AspireDEX.Blockchain.Contracts.Factory.ContractDefinition;

namespace AspireDEX.Blockchain.Contracts.Factory
{
    public partial class FactoryService: FactoryServiceBase
    {
        public static Task<TransactionReceipt> DeployContractAndWaitForReceiptAsync(Nethereum.Web3.IWeb3 web3, FactoryDeployment factoryDeployment, CancellationTokenSource cancellationTokenSource = null)
        {
            return web3.Eth.GetContractDeploymentHandler<FactoryDeployment>().SendRequestAndWaitForReceiptAsync(factoryDeployment, cancellationTokenSource);
        }

        public static Task<string> DeployContractAsync(Nethereum.Web3.IWeb3 web3, FactoryDeployment factoryDeployment)
        {
            return web3.Eth.GetContractDeploymentHandler<FactoryDeployment>().SendRequestAsync(factoryDeployment);
        }

        public static async Task<FactoryService> DeployContractAndGetServiceAsync(Nethereum.Web3.IWeb3 web3, FactoryDeployment factoryDeployment, CancellationTokenSource cancellationTokenSource = null)
        {
            var receipt = await DeployContractAndWaitForReceiptAsync(web3, factoryDeployment, cancellationTokenSource);
            return new FactoryService(web3, receipt.ContractAddress);
        }

        public FactoryService(Nethereum.Web3.IWeb3 web3, string contractAddress) : base(web3, contractAddress)
        {
        }

    }


    public partial class FactoryServiceBase: ContractWeb3ServiceBase
    {

        public FactoryServiceBase(Nethereum.Web3.IWeb3 web3, string contractAddress) : base(web3, contractAddress)
        {
        }

        public Task<string> AllPairsQueryAsync(AllPairsFunction allPairsFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<AllPairsFunction, string>(allPairsFunction, blockParameter);
        }

        
        public virtual Task<string> AllPairsQueryAsync(BigInteger returnValue1, BlockParameter blockParameter = null)
        {
            var allPairsFunction = new AllPairsFunction();
                allPairsFunction.ReturnValue1 = returnValue1;
            
            return ContractHandler.QueryAsync<AllPairsFunction, string>(allPairsFunction, blockParameter);
        }

        public Task<BigInteger> AllPairsLengthQueryAsync(AllPairsLengthFunction allPairsLengthFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<AllPairsLengthFunction, BigInteger>(allPairsLengthFunction, blockParameter);
        }

        
        public virtual Task<BigInteger> AllPairsLengthQueryAsync(BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<AllPairsLengthFunction, BigInteger>(null, blockParameter);
        }

        public virtual Task<string> CreatePairRequestAsync(CreatePairFunction createPairFunction)
        {
             return ContractHandler.SendRequestAsync(createPairFunction);
        }

        public virtual Task<TransactionReceipt> CreatePairRequestAndWaitForReceiptAsync(CreatePairFunction createPairFunction, CancellationTokenSource cancellationToken = null)
        {
             return ContractHandler.SendRequestAndWaitForReceiptAsync(createPairFunction, cancellationToken);
        }

        public virtual Task<string> CreatePairRequestAsync(string tokenA, string tokenB)
        {
            var createPairFunction = new CreatePairFunction();
                createPairFunction.TokenA = tokenA;
                createPairFunction.TokenB = tokenB;
            
             return ContractHandler.SendRequestAsync(createPairFunction);
        }

        public virtual Task<TransactionReceipt> CreatePairRequestAndWaitForReceiptAsync(string tokenA, string tokenB, CancellationTokenSource cancellationToken = null)
        {
            var createPairFunction = new CreatePairFunction();
                createPairFunction.TokenA = tokenA;
                createPairFunction.TokenB = tokenB;
            
             return ContractHandler.SendRequestAndWaitForReceiptAsync(createPairFunction, cancellationToken);
        }

        public Task<string> GetPairQueryAsync(GetPairFunction getPairFunction, BlockParameter blockParameter = null)
        {
            return ContractHandler.QueryAsync<GetPairFunction, string>(getPairFunction, blockParameter);
        }

        
        public virtual Task<string> GetPairQueryAsync(string returnValue1, string returnValue2, BlockParameter blockParameter = null)
        {
            var getPairFunction = new GetPairFunction();
                getPairFunction.ReturnValue1 = returnValue1;
                getPairFunction.ReturnValue2 = returnValue2;
            
            return ContractHandler.QueryAsync<GetPairFunction, string>(getPairFunction, blockParameter);
        }

        public override List<Type> GetAllFunctionTypes()
        {
            return new List<Type>
            {
                typeof(AllPairsFunction),
                typeof(AllPairsLengthFunction),
                typeof(CreatePairFunction),
                typeof(GetPairFunction)
            };
        }

        public override List<Type> GetAllEventTypes()
        {
            return new List<Type>
            {
                typeof(PairCreatedEventDTO)
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
