using System;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Numerics;
using Nethereum.Hex.HexTypes;
using Nethereum.ABI.FunctionEncoding.Attributes;
using Nethereum.RPC.Eth.DTOs;
using Nethereum.Contracts.CQS;
using Nethereum.Contracts;
using System.Threading;

namespace AspireDEX.Blockchain.Contracts.Router.ContractDefinition
{


    public partial class RouterDeployment : RouterDeploymentBase
    {
        public RouterDeployment() : base(BYTECODE) { }
        public RouterDeployment(string byteCode) : base(byteCode) { }
    }

    public class RouterDeploymentBase : ContractDeploymentMessage
    {
        public static string BYTECODE = "";
        public RouterDeploymentBase() : base(BYTECODE) { }
        public RouterDeploymentBase(string byteCode) : base(byteCode) { }
        [Parameter("address", "_factory", 1)]
        public virtual string Factory { get; set; }
    }

    public partial class AddLiquidityFunction : AddLiquidityFunctionBase { }

    [Function("addLiquidity", typeof(AddLiquidityOutputDTO))]
    public class AddLiquidityFunctionBase : FunctionMessage
    {
        [Parameter("address", "tokenA", 1)]
        public virtual string TokenA { get; set; }
        [Parameter("address", "tokenB", 2)]
        public virtual string TokenB { get; set; }
        [Parameter("uint256", "amountADesired", 3)]
        public virtual BigInteger AmountADesired { get; set; }
        [Parameter("uint256", "amountBDesired", 4)]
        public virtual BigInteger AmountBDesired { get; set; }
        [Parameter("uint256", "amountAMin", 5)]
        public virtual BigInteger AmountAMin { get; set; }
        [Parameter("uint256", "amountBMin", 6)]
        public virtual BigInteger AmountBMin { get; set; }
        [Parameter("address", "to", 7)]
        public virtual string To { get; set; }
        [Parameter("uint256", "deadline", 8)]
        public virtual BigInteger Deadline { get; set; }
    }

    public partial class FactoryFunction : FactoryFunctionBase { }

    [Function("factory", "address")]
    public class FactoryFunctionBase : FunctionMessage
    {

    }

    public partial class GetAmountOutFunction : GetAmountOutFunctionBase { }

    [Function("getAmountOut", "uint256")]
    public class GetAmountOutFunctionBase : FunctionMessage
    {
        [Parameter("uint256", "amountIn", 1)]
        public virtual BigInteger AmountIn { get; set; }
        [Parameter("uint256", "reserveIn", 2)]
        public virtual BigInteger ReserveIn { get; set; }
        [Parameter("uint256", "reserveOut", 3)]
        public virtual BigInteger ReserveOut { get; set; }
    }

    public partial class GetAmountsOutFunction : GetAmountsOutFunctionBase { }

    [Function("getAmountsOut", "uint256[]")]
    public class GetAmountsOutFunctionBase : FunctionMessage
    {
        [Parameter("uint256", "amountIn", 1)]
        public virtual BigInteger AmountIn { get; set; }
        [Parameter("address[]", "path", 2)]
        public virtual List<string> Path { get; set; }
    }

    public partial class RemoveLiquidityFunction : RemoveLiquidityFunctionBase { }

    [Function("removeLiquidity", typeof(RemoveLiquidityOutputDTO))]
    public class RemoveLiquidityFunctionBase : FunctionMessage
    {
        [Parameter("address", "tokenA", 1)]
        public virtual string TokenA { get; set; }
        [Parameter("address", "tokenB", 2)]
        public virtual string TokenB { get; set; }
        [Parameter("uint256", "liquidity", 3)]
        public virtual BigInteger Liquidity { get; set; }
        [Parameter("uint256", "amountAMin", 4)]
        public virtual BigInteger AmountAMin { get; set; }
        [Parameter("uint256", "amountBMin", 5)]
        public virtual BigInteger AmountBMin { get; set; }
        [Parameter("address", "to", 6)]
        public virtual string To { get; set; }
        [Parameter("uint256", "deadline", 7)]
        public virtual BigInteger Deadline { get; set; }
    }

    public partial class SwapExactTokensForTokensFunction : SwapExactTokensForTokensFunctionBase { }

    [Function("swapExactTokensForTokens", "uint256[]")]
    public class SwapExactTokensForTokensFunctionBase : FunctionMessage
    {
        [Parameter("uint256", "amountIn", 1)]
        public virtual BigInteger AmountIn { get; set; }
        [Parameter("uint256", "amountOutMin", 2)]
        public virtual BigInteger AmountOutMin { get; set; }
        [Parameter("address[]", "path", 3)]
        public virtual List<string> Path { get; set; }
        [Parameter("address", "to", 4)]
        public virtual string To { get; set; }
        [Parameter("uint256", "deadline", 5)]
        public virtual BigInteger Deadline { get; set; }
    }

    public partial class AddLiquidityOutputDTO : AddLiquidityOutputDTOBase { }

    [FunctionOutput]
    public class AddLiquidityOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("uint256", "amountA", 1)]
        public virtual BigInteger AmountA { get; set; }
        [Parameter("uint256", "amountB", 2)]
        public virtual BigInteger AmountB { get; set; }
        [Parameter("uint256", "liquidity", 3)]
        public virtual BigInteger Liquidity { get; set; }
    }

    public partial class FactoryOutputDTO : FactoryOutputDTOBase { }

    [FunctionOutput]
    public class FactoryOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("address", "", 1)]
        public virtual string ReturnValue1 { get; set; }
    }

    public partial class GetAmountOutOutputDTO : GetAmountOutOutputDTOBase { }

    [FunctionOutput]
    public class GetAmountOutOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("uint256", "amountOut", 1)]
        public virtual BigInteger AmountOut { get; set; }
    }

    public partial class GetAmountsOutOutputDTO : GetAmountsOutOutputDTOBase { }

    [FunctionOutput]
    public class GetAmountsOutOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("uint256[]", "amounts", 1)]
        public virtual List<BigInteger> Amounts { get; set; }
    }

    public partial class RemoveLiquidityOutputDTO : RemoveLiquidityOutputDTOBase { }

    [FunctionOutput]
    public class RemoveLiquidityOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("uint256", "amountA", 1)]
        public virtual BigInteger AmountA { get; set; }
        [Parameter("uint256", "amountB", 2)]
        public virtual BigInteger AmountB { get; set; }
    }


}
