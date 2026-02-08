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
    private readonly AcpProxy _proxy;

    public AcpProxyProcessAdapter(
        string agent,
        Stream stdout,
        TextWriter stderr,
        bool directSpawn) => _proxy = new AcpProxy(agent, stdout, stderr, directSpawn);

    public void Cancel() => _proxy.Cancel();

    public Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken) => _proxy.RunAsync(stdin, cancellationToken);

    public void Dispose() => _proxy.Dispose();
}

internal sealed class AcpProxyRunner
{
    private readonly Func<string, Stream, TextWriter, bool, IAcpProxyProcess> _proxyFactory;
    private readonly Func<Stream> _stdinFactory;
    private readonly Func<Stream> _stdoutFactory;
    private readonly TextWriter _stderr;
    private readonly Func<bool> _directSpawnResolver;
    private readonly Action<ConsoleCancelEventHandler> _subscribeCancelHandler;
    private readonly Action<ConsoleCancelEventHandler> _unsubscribeCancelHandler;

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
        Func<string, Stream, TextWriter, bool, IAcpProxyProcess> proxyFactory,
        Func<Stream> stdinFactory,
        Func<Stream> stdoutFactory,
        TextWriter stderr,
        Func<bool> directSpawnResolver,
        Action<ConsoleCancelEventHandler> subscribeCancelHandler,
        Action<ConsoleCancelEventHandler> unsubscribeCancelHandler)
    {
        _proxyFactory = proxyFactory;
        _stdinFactory = stdinFactory;
        _stdoutFactory = stdoutFactory;
        _stderr = stderr;
        _directSpawnResolver = directSpawnResolver;
        _subscribeCancelHandler = subscribeCancelHandler;
        _unsubscribeCancelHandler = unsubscribeCancelHandler;
    }

    public async Task<int> RunAsync(string? agent, CancellationToken cancellationToken)
    {
        var resolvedAgent = string.IsNullOrWhiteSpace(agent) ? "claude" : agent;
        var directSpawn = _directSpawnResolver();

        try
        {
            using var proxy = _proxyFactory(
                resolvedAgent,
                _stdoutFactory(),
                _stderr,
                directSpawn);

            ConsoleCancelEventHandler handler = (_, e) =>
            {
                e.Cancel = true;
                proxy.Cancel();
            };

            _subscribeCancelHandler(handler);
            try
            {
                return await proxy.RunAsync(_stdinFactory(), cancellationToken).ConfigureAwait(false);
            }
            finally
            {
                _unsubscribeCancelHandler(handler);
            }
        }
        catch (ArgumentException ex)
        {
            await _stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            await _stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await _stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await _stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
        catch (NotSupportedException ex)
        {
            await _stderr.WriteLineAsync(ex.Message).ConfigureAwait(false);
            return 1;
        }
    }
}
