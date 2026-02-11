namespace ContainAI.Cli.Host;

internal sealed partial class AcpProxyRunner
{
    private async Task<int> RunProxyAsync(string resolvedAgent, CancellationToken cancellationToken)
    {
        using var proxy = proxyFactory(
            resolvedAgent,
            stdoutFactory(),
            stderr);

        ConsoleCancelEventHandler handler = (_, e) =>
        {
            e.Cancel = true;
            proxy.Cancel();
        };

        subscribeCancelHandler(handler);
        try
        {
            return await proxy.RunAsync(stdinFactory(), cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            unsubscribeCancelHandler(handler);
        }
    }

    private async Task<int> WriteErrorAndReturnAsync(string message)
    {
        await stderr.WriteLineAsync(message).ConfigureAwait(false);
        return 1;
    }
}
