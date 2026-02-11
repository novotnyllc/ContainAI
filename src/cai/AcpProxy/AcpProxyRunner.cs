using System.Runtime.CompilerServices;

[assembly: InternalsVisibleTo("AgentClientProtocol.Proxy.Tests")]
[assembly: InternalsVisibleTo("ContainAI.Cli.Tests")]

namespace ContainAI.Cli.Host;

internal sealed class AcpProxyRunner
{
    private readonly Func<string, Stream, TextWriter, IAcpProxyProcess> proxyFactory;
    private readonly Func<Stream> stdinFactory;
    private readonly Func<Stream> stdoutFactory;
    private readonly AcpProxyOperationExecutor operationExecutor;
    private readonly TextWriter stderr;
    private readonly Action<ConsoleCancelEventHandler> subscribeCancelHandler;
    private readonly Action<ConsoleCancelEventHandler> unsubscribeCancelHandler;

    public AcpProxyRunner()
        : this(
            static (agent, stdout, stderr) => new AcpProxyProcessAdapter(agent, stdout, stderr),
            static () => Console.OpenStandardInput(),
            static () => Console.OpenStandardOutput(),
            Console.Error,
            static handler => Console.CancelKeyPress += handler,
            static handler => Console.CancelKeyPress -= handler)
    {
    }

    internal AcpProxyRunner(
        Func<string, Stream, TextWriter, IAcpProxyProcess> proxyFactoryFactory,
        Func<Stream> standardInputFactory,
        Func<Stream> standardOutputFactory,
        TextWriter errorWriter,
        Action<ConsoleCancelEventHandler> subscribeCancelKeyHandler,
        Action<ConsoleCancelEventHandler> unsubscribeCancelKeyHandler)
    {
        proxyFactory = proxyFactoryFactory;
        stdinFactory = standardInputFactory;
        stdoutFactory = standardOutputFactory;
        stderr = errorWriter;
        operationExecutor = new AcpProxyOperationExecutor(stderr);
        subscribeCancelHandler = subscribeCancelKeyHandler;
        unsubscribeCancelHandler = unsubscribeCancelKeyHandler;
    }

    public async Task<int> RunAsync(string? agent, CancellationToken cancellationToken)
    {
        var resolvedAgent = string.IsNullOrWhiteSpace(agent) ? "claude" : agent;
        return await operationExecutor
            .ExecuteAsync(() => RunProxyAsync(resolvedAgent, cancellationToken), cancellationToken)
            .ConfigureAwait(false);
    }

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
}
