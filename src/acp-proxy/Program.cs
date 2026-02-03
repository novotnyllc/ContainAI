// ContainAI ACP Proxy CLI
// Usage: acp-proxy proxy <agent>

using System.CommandLine;
using System.CommandLine.Parsing;
using ContainAI.Acp;

namespace ContainAI.AcpProxy;

public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        var rootCommand = new RootCommand("ACP terminating proxy for ContainAI");

        // Add the proxy subcommand
        var proxyCommand = CreateProxyCommand();
        rootCommand.Subcommands.Add(proxyCommand);

        return await rootCommand.Parse(args).InvokeAsync();
    }

    private static Command CreateProxyCommand()
    {
        var agentArgument = new Argument<string>("agent")
        {
            Description = "The agent binary to proxy (any agent supporting --acp flag)",
            Arity = ArgumentArity.ZeroOrOne,
            DefaultValueFactory = _ => "claude"
        };

        var proxyCommand = new Command("proxy", "Start the ACP proxy server");
        proxyCommand.Arguments.Add(agentArgument);

        proxyCommand.SetAction(async (parseResult, cancellationToken) =>
        {
            var agent = parseResult.GetValue(agentArgument) ?? "claude";
            var testMode = Environment.GetEnvironmentVariable("CAI_ACP_TEST_MODE") == "1";
            var directSpawn = Environment.GetEnvironmentVariable("CAI_ACP_DIRECT_SPAWN") == "1";

            try
            {
                using var proxy = new Acp.AcpProxy(
                    agent,
                    Console.OpenStandardOutput(),
                    Console.Error,
                    testMode,
                    directSpawn);

                // Set up console cancel handler for graceful shutdown
                Console.CancelKeyPress += (_, e) =>
                {
                    e.Cancel = true;
                    proxy.Cancel();
                };

                return await proxy.RunAsync(Console.OpenStandardInput(), cancellationToken);
            }
            catch (ArgumentException ex)
            {
                await Console.Error.WriteLineAsync(ex.Message);
                return 1;
            }
        });

        return proxyCommand;
    }
}
