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
    // NOTE: regenerated against the current Router.sol — this Router has no addLiquidity/
    // removeLiquidity/getAmountsOut of its own (unlike a classic Uniswap V2 Router). Liquidity
    // is provisioned directly on Pair (transfer tokens to the pair, then Pair.mint/burn); this
    // Router only quotes and executes swaps, with oracle-deviation and circuit-breaker checks.

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
        [Parameter("address", "_oracle", 2)]
        public virtual string Oracle { get; set; }
    }

    public partial class FactoryFunction : FactoryFunctionBase { }

    [Function("factory", "address")]
    public class FactoryFunctionBase : FunctionMessage
    {

    }

    public partial class OracleFunction : OracleFunctionBase { }

    [Function("oracle", "address")]
    public class OracleFunctionBase : FunctionMessage
    {

    }

    public partial class QuoteExactInputFunction : QuoteExactInputFunctionBase { }

    [Function("quoteExactInput", "uint256[]")]
    public class QuoteExactInputFunctionBase : FunctionMessage
    {
        [Parameter("uint256", "amountIn", 1)]
        public virtual BigInteger AmountIn { get; set; }
        [Parameter("address[]", "path", 2)]
        public virtual List<string> Path { get; set; }
    }

    public partial class QuoteExactOutputFunction : QuoteExactOutputFunctionBase { }

    [Function("quoteExactOutput", "uint256[]")]
    public class QuoteExactOutputFunctionBase : FunctionMessage
    {
        [Parameter("uint256", "amountOut", 1)]
        public virtual BigInteger AmountOut { get; set; }
        [Parameter("address[]", "path", 2)]
        public virtual List<string> Path { get; set; }
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

    public partial class SwapTokensForExactTokensFunction : SwapTokensForExactTokensFunctionBase { }

    [Function("swapTokensForExactTokens", "uint256[]")]
    public class SwapTokensForExactTokensFunctionBase : FunctionMessage
    {
        [Parameter("uint256", "amountOut", 1)]
        public virtual BigInteger AmountOut { get; set; }
        [Parameter("uint256", "amountInMax", 2)]
        public virtual BigInteger AmountInMax { get; set; }
        [Parameter("address[]", "path", 3)]
        public virtual List<string> Path { get; set; }
        [Parameter("address", "to", 4)]
        public virtual string To { get; set; }
        [Parameter("uint256", "deadline", 5)]
        public virtual BigInteger Deadline { get; set; }
    }

    public partial class ExpiredError : ExpiredErrorBase { }

    [Error("Expired")]
    public class ExpiredErrorBase : IErrorDTO
    {
        [Parameter("uint256", "deadline", 1)]
        public virtual BigInteger Deadline { get; set; }
        [Parameter("uint256", "current", 2)]
        public virtual BigInteger Current { get; set; }
    }

    public partial class InsufficientOutputAmountError : InsufficientOutputAmountErrorBase { }

    [Error("InsufficientOutputAmount")]
    public class InsufficientOutputAmountErrorBase : IErrorDTO
    {
        [Parameter("uint256", "got", 1)]
        public virtual BigInteger Got { get; set; }
        [Parameter("uint256", "min", 2)]
        public virtual BigInteger Min { get; set; }
    }

    public partial class ExcessiveInputAmountError : ExcessiveInputAmountErrorBase { }

    [Error("ExcessiveInputAmount")]
    public class ExcessiveInputAmountErrorBase : IErrorDTO
    {
        [Parameter("uint256", "got", 1)]
        public virtual BigInteger Got { get; set; }
        [Parameter("uint256", "max", 2)]
        public virtual BigInteger Max { get; set; }
    }

    public partial class OraclePriceDeviationError : OraclePriceDeviationErrorBase { }

    [Error("OraclePriceDeviation")]
    public class OraclePriceDeviationErrorBase : IErrorDTO
    {
        [Parameter("uint256", "executionPrice", 1)]
        public virtual BigInteger ExecutionPrice { get; set; }
        [Parameter("uint256", "oraclePrice", 2)]
        public virtual BigInteger OraclePrice { get; set; }
        [Parameter("uint256", "deviation", 3)]
        public virtual BigInteger Deviation { get; set; }
    }

    public partial class InvalidPathError : InvalidPathErrorBase { }

    [Error("InvalidPath")]
    public class InvalidPathErrorBase : IErrorDTO
    {
    }

    public partial class PairDoesNotExistError : PairDoesNotExistErrorBase { }

    [Error("PairDoesNotExist")]
    public class PairDoesNotExistErrorBase : IErrorDTO
    {
        [Parameter("address", "tokenA", 1)]
        public virtual string TokenA { get; set; }
        [Parameter("address", "tokenB", 2)]
        public virtual string TokenB { get; set; }
    }

    public partial class CircuitBreakerActiveError : CircuitBreakerActiveErrorBase { }

    [Error("CircuitBreakerActive")]
    public class CircuitBreakerActiveErrorBase : IErrorDTO
    {
        [Parameter("address", "pair", 1)]
        public virtual string Pair { get; set; }
    }

    public partial class FactoryOutputDTO : FactoryOutputDTOBase { }

    [FunctionOutput]
    public class FactoryOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("address", "", 1)]
        public virtual string ReturnValue1 { get; set; }
    }

    public partial class OracleOutputDTO : OracleOutputDTOBase { }

    [FunctionOutput]
    public class OracleOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("address", "", 1)]
        public virtual string ReturnValue1 { get; set; }
    }

    public partial class QuoteExactInputOutputDTO : QuoteExactInputOutputDTOBase { }

    [FunctionOutput]
    public class QuoteExactInputOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("uint256[]", "amounts", 1)]
        public virtual List<BigInteger> Amounts { get; set; }
    }

    public partial class QuoteExactOutputOutputDTO : QuoteExactOutputOutputDTOBase { }

    [FunctionOutput]
    public class QuoteExactOutputOutputDTOBase : IFunctionOutputDTO 
    {
        [Parameter("uint256[]", "amounts", 1)]
        public virtual List<BigInteger> Amounts { get; set; }
    }
}
