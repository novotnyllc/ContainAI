using System.Runtime.CompilerServices;
using AgentClientProtocol.Proxy;

[assembly: InternalsVisibleTo("AgentClientProtocol.Proxy.Tests")]
[assembly: InternalsVisibleTo("ContainAI.Cli.Tests")]

namespace ContainAI.Cli.Host;

internal interface IAcpProxyProcess : IDisposable
{
    void Cancel();

    Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken);
}

internal sealed class AcpProxyProcessAdapter : IAcpProxyProcess
{
    private readonly AcpProxy proxy;

    public AcpProxyProcessAdapter(
        string agent,
        Stream stdout,
        TextWriter stderr) => proxy = new AcpProxy(agent, stdout, stderr);

    public void Cancel() => proxy.Cancel();

    public Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken) => proxy.RunAsync(stdin, cancellationToken);

    public void Dispose() => proxy.Dispose();
}

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
        catch (ArgumentException ex)
        {
            await stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
        catch (NotSupportedException ex)
        {
            await stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
    }
}
