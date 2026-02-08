using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly AcpProxyRunner acpProxyRunner;
    private readonly NativeLifecycleCommandRuntime nativeLifecycleRuntime;

    public CaiCommandRuntime(
        AcpProxyRunner proxyRunner,
        NativeLifecycleCommandRuntime? lifecycleRuntime = null)
    {
        acpProxyRunner = proxyRunner;
        nativeLifecycleRuntime = lifecycleRuntime ?? new NativeLifecycleCommandRuntime();
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return nativeLifecycleRuntime.RunRunAsync(options, cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return nativeLifecycleRuntime.RunShellAsync(options, cancellationToken);
    }

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return nativeLifecycleRuntime.RunExecAsync(options, cancellationToken);
    }

    public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return NativeLifecycleCommandRuntime.RunDockerAsync(options, cancellationToken);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return nativeLifecycleRuntime.RunStatusAsync(options, cancellationToken);
    }

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => acpProxyRunner.RunAsync(agent, cancellationToken);

    public Task<int> RunNativeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunAsync(args, cancellationToken);

}
