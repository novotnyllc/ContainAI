using ContainAI.Acp;

namespace ContainAI.Cli.Host;

internal sealed class AcpProxyRunner
{
    public async Task<int> RunAsync(string agent, CancellationToken cancellationToken)
    {
        var directSpawn = Environment.GetEnvironmentVariable("CAI_ACP_DIRECT_SPAWN") == "1";

        try
        {
            using var proxy = new AcpProxy(
                agent,
                Console.OpenStandardOutput(),
                Console.Error,
                directSpawn);

            ConsoleCancelEventHandler handler = (_, e) =>
            {
                e.Cancel = true;
                proxy.Cancel();
            };

            Console.CancelKeyPress += handler;
            try
            {
                return await proxy.RunAsync(Console.OpenStandardInput(), cancellationToken);
            }
            finally
            {
                Console.CancelKeyPress -= handler;
            }
        }
        catch (ArgumentException ex)
        {
            await Console.Error.WriteLineAsync(ex.Message);
            return 1;
        }
    }
}
