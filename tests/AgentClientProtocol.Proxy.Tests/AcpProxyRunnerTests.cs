using System.Reflection;
using ContainAI.Cli.Host;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AcpProxyRunnerTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task RunAsync_AgentMissing_DefaultsToClaude(string? inputAgent)
    {
        string? capturedAgent = null;
        var stdout = new MemoryStream();
        var stderr = new StringWriter();

        var runner = CreateRunner(
            (agent, _, _, _) =>
            {
                capturedAgent = agent;
                return new FakeProxy(exitCode: 17);
            },
            stdin: Stream.Null,
            stdout: stdout,
            stderr: stderr);

        var exitCode = await runner.RunAsync(inputAgent, TestContext.Current.CancellationToken);

        Assert.Equal(17, exitCode);
        Assert.Equal("claude", capturedAgent);
        Assert.Equal(0, stdout.Length);
        Assert.Equal(string.Empty, stderr.ToString());
    }

    [Fact]
    public async Task RunAsync_ConsoleCancelHandler_CancelsProxy()
    {
        var handlerRegistered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        ConsoleCancelEventHandler? registeredHandler = null;
        var stdout = new MemoryStream();
        var stderr = new StringWriter();
        using var proxy = new FakeProxy(exitCode: 0, completeOnCancel: true);

        var runner = CreateRunner(
            (_, _, _, _) => proxy,
            stdin: Stream.Null,
            stdout: stdout,
            stderr: stderr,
            subscribeCancelHandler: handler =>
            {
                registeredHandler = handler;
                handlerRegistered.TrySetResult();
            },
            unsubscribeCancelHandler: handler =>
            {
                if (ReferenceEquals(registeredHandler, handler))
                {
                    registeredHandler = null;
                }
            });

        var runTask = runner.RunAsync("claude", TestContext.Current.CancellationToken);

        await handlerRegistered.Task.WaitAsync(TestContext.Current.CancellationToken);
        var cancelArgs = CreateCancelEventArgs();
        Assert.NotNull(registeredHandler);

        registeredHandler.Invoke(this, cancelArgs);

        var exitCode = await runTask.ConfigureAwait(true);

        Assert.True(proxy.CancelCalled);
        Assert.True(cancelArgs.Cancel);
        Assert.Equal(0, exitCode);
        Assert.Null(registeredHandler);
        Assert.Equal(0, stdout.Length);
        Assert.Equal(string.Empty, stderr.ToString());
    }

    [Fact]
    public async Task RunAsync_CanceledToken_ReturnsZero()
    {
        var stdout = new MemoryStream();
        var stderr = new StringWriter();
        var cancellationToken = new CancellationToken(canceled: true);

        var runner = CreateRunner(
            (_, _, _, _) => new FakeProxy(
                runAsync: (_, ct) =>
                {
                    ct.ThrowIfCancellationRequested();
                    return Task.FromResult(123);
                }),
            stdin: Stream.Null,
            stdout: stdout,
            stderr: stderr);

        var exitCode = await runner.RunAsync("claude", cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Equal(0, stdout.Length);
        Assert.Equal(string.Empty, stderr.ToString());
    }

    [Fact]
    public async Task RunAsync_ArgumentError_WritesOnlyStderr()
    {
        var stdout = new MemoryStream();
        var stderr = new StringWriter();

        var runner = CreateRunner(
            (_, _, _, _) => throw new ArgumentException("agent invalid"),
            stdin: Stream.Null,
            stdout: stdout,
            stderr: stderr);

        var exitCode = await runner.RunAsync("bad-agent", TestContext.Current.CancellationToken);

        Assert.Equal(1, exitCode);
        Assert.Equal(0, stdout.Length);
        Assert.Contains("agent invalid", stderr.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_StartupError_WritesOnlyStderr()
    {
        var stdout = new MemoryStream();
        var stderr = new StringWriter();

        var runner = CreateRunner(
            (_, _, _, _) => throw new InvalidOperationException("startup failed"),
            stdin: Stream.Null,
            stdout: stdout,
            stderr: stderr);

        var exitCode = await runner.RunAsync("claude", TestContext.Current.CancellationToken);

        Assert.Equal(1, exitCode);
        Assert.Equal(0, stdout.Length);
        Assert.Contains("startup failed", stderr.ToString(), StringComparison.Ordinal);
    }

    private static AcpProxyRunner CreateRunner(
        Func<string, Stream, TextWriter, bool, IAcpProxyProcess> proxyFactory,
        Stream stdin,
        Stream stdout,
        TextWriter stderr,
        bool directSpawn = false,
        Action<ConsoleCancelEventHandler>? subscribeCancelHandler = null,
        Action<ConsoleCancelEventHandler>? unsubscribeCancelHandler = null)
    {
        return new AcpProxyRunner(
            proxyFactory,
            () => stdin,
            () => stdout,
            stderr,
            () => directSpawn,
            subscribeCancelHandler ?? (_ => { }),
            unsubscribeCancelHandler ?? (_ => { }));
    }

    private static ConsoleCancelEventArgs CreateCancelEventArgs()
    {
        var constructor = typeof(ConsoleCancelEventArgs).GetConstructor(
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            binder: null,
            [typeof(ConsoleSpecialKey)],
            modifiers: null);

        Assert.NotNull(constructor);
        return (ConsoleCancelEventArgs)constructor.Invoke([ConsoleSpecialKey.ControlC]);
    }

    private sealed class FakeProxy : IAcpProxyProcess
    {
        private readonly int _exitCode;
        private readonly Func<Stream, CancellationToken, Task<int>>? _runAsync;
        private readonly bool _completeOnCancel;
        private readonly TaskCompletionSource<int> _completion =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public bool CancelCalled { get; private set; }

        public FakeProxy(
            int exitCode = 0,
            Func<Stream, CancellationToken, Task<int>>? runAsync = null,
            bool completeOnCancel = false)
        {
            _exitCode = exitCode;
            _runAsync = runAsync;
            _completeOnCancel = completeOnCancel;
        }

        public void Cancel()
        {
            CancelCalled = true;

            if (_completeOnCancel)
            {
                _completion.TrySetResult(_exitCode);
            }
        }

        public Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken)
        {
            if (_runAsync is not null)
            {
                return _runAsync(stdin, cancellationToken);
            }

            if (_completeOnCancel)
            {
                return _completion.Task;
            }

            return Task.FromResult(_exitCode);
        }

        public void Dispose()
        {
        }
    }
}
