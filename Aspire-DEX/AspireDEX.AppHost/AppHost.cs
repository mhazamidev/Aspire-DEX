using Projects;

var builder = DistributedApplication.CreateBuilder(args);

var cache = builder.AddRedis("cache");

// Blockchain configuration lives as Aspire parameters, not in appsettings.json.
// Set real values with:
//   dotnet user-secrets set "Parameters:blockchain-rpc-url" "https://ethereum-sepolia-rpc.publicnode.com" --project AspireDEX.AppHost
//   dotnet user-secrets set "Parameters:blockchain-private-key" "0x..." --project AspireDEX.AppHost
//   dotnet user-secrets set "Parameters:blockchain-chain-id" "11155111" --project AspireDEX.AppHost
//   dotnet user-secrets set "Parameters:router-address" "0x..." --project AspireDEX.AppHost
//   dotnet user-secrets set "Parameters:factory-address" "0x..." --project AspireDEX.AppHost
// The private-key parameter is marked secret so Aspire never logs or displays it in the dashboard.
var rpcUrl = builder.AddParameter("blockchain-rpc-url");
var privateKey = builder.AddParameter("blockchain-private-key", secret: true);
var chainId = builder.AddParameter("blockchain-chain-id");
var routerAddress = builder.AddParameter("router-address");
var factoryAddress = builder.AddParameter("factory-address");

var apiService = builder.AddProject<AspireDEX_ApiService>("apiservice")
    .WithHttpHealthCheck("/health")
    .WithEnvironment("Blockchain__RpcUrl", rpcUrl)
    .WithEnvironment("Blockchain__PrivateKey", privateKey)
    .WithEnvironment("Blockchain__ChainId", chainId)
    .WithEnvironment("Contracts__Router", routerAddress)
    .WithEnvironment("Contracts__Factory", factoryAddress);

builder.AddProject<AspireDEX_Web>("webfrontend")
    .WithExternalHttpEndpoints()
    .WithHttpHealthCheck("/health")
    .WithReference(cache)
    .WaitFor(cache)
    .WithReference(apiService)
    .WaitFor(apiService);

builder.Build().Run();
