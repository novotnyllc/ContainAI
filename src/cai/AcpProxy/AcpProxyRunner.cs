using System.Runtime.CompilerServices;

[assembly: InternalsVisibleTo("AgentClientProtocol.Proxy.Tests")]
[assembly: InternalsVisibleTo("ContainAI.Cli.Tests")]

namespace ContainAI.Cli.Host;

internal sealed class AcpProxyRunner
{
    private readonly Func<string, Stream, TextWriter, IAcpProxyProcess> proxyFactory;
    private readonly Func<Stream> stdinFactory;
    private readonly Func<Stream> stdoutFactory;
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
        subscribeCancelHandler = subscribeCancelKeyHandler;
        unsubscribeCancelHandler = unsubscribeCancelKeyHandler;
    }

    public async Task<int> RunAsync(string? agent, CancellationToken cancellationToken)
    {
        var resolvedAgent = string.IsNullOrWhiteSpace(agent) ? "claude" : agent;

        try
        {
            return await RunProxyAsync(resolvedAgent, cancellationToken).ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
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

    private async Task<int> WriteErrorAndReturnAsync(string message)
    {
        await stderr.WriteLineAsync(message).ConfigureAwait(false);
        return 1;
    }
}
