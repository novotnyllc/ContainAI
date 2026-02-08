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
        TextWriter stderr,
        bool directSpawn) => proxy = new AcpProxy(agent, stdout, stderr, directSpawn);

    public void Cancel() => proxy.Cancel();

    public Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken) => proxy.RunAsync(stdin, cancellationToken);

    public void Dispose() => proxy.Dispose();
}

internal sealed class AcpProxyRunner
{
    private readonly Func<string, Stream, TextWriter, bool, IAcpProxyProcess> proxyFactory;
    private readonly Func<Stream> stdinFactory;
    private readonly Func<Stream> stdoutFactory;
    private readonly TextWriter stderr;
    private readonly Func<bool> directSpawnResolver;
    private readonly Action<ConsoleCancelEventHandler> subscribeCancelHandler;
    private readonly Action<ConsoleCancelEventHandler> unsubscribeCancelHandler;

    public AcpProxyRunner()
        : this(
            static (agent, stdout, stderr, directSpawn) => new AcpProxyProcessAdapter(agent, stdout, stderr, directSpawn),
            static () => Console.OpenStandardInput(),
            static () => Console.OpenStandardOutput(),
            Console.Error,
            static () => Environment.GetEnvironmentVariable("CAI_ACP_DIRECT_SPAWN") == "1",
            static handler => Console.CancelKeyPress += handler,
            static handler => Console.CancelKeyPress -= handler)
    {
    }

    internal AcpProxyRunner(
        Func<string, Stream, TextWriter, bool, IAcpProxyProcess> proxyFactoryFactory,
        Func<Stream> standardInputFactory,
        Func<Stream> standardOutputFactory,
        TextWriter errorWriter,
        Func<bool> directSpawnValueResolver,
        Action<ConsoleCancelEventHandler> subscribeCancelKeyHandler,
        Action<ConsoleCancelEventHandler> unsubscribeCancelKeyHandler)
    {
        proxyFactory = proxyFactoryFactory;
        stdinFactory = standardInputFactory;
        stdoutFactory = standardOutputFactory;
        stderr = errorWriter;
        directSpawnResolver = directSpawnValueResolver;
        subscribeCancelHandler = subscribeCancelKeyHandler;
        unsubscribeCancelHandler = unsubscribeCancelKeyHandler;
    }

    public async Task<int> RunAsync(string? agent, CancellationToken cancellationToken)
    {
        var resolvedAgent = string.IsNullOrWhiteSpace(agent) ? "claude" : agent;
        var directSpawn = directSpawnResolver();

        try
        {
            using var proxy = proxyFactory(
                resolvedAgent,
                stdoutFactory(),
                stderr,
                directSpawn);

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
