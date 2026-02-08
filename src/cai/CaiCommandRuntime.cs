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
        var args = new List<string>
        {
            "docker",
        };

        AppendTokens(args, options.DockerArgs);
        return nativeLifecycleRuntime.RunAsync(args, cancellationToken);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>
        {
            "status",
        };

        if (options.Json)
        {
            args.Add("--json");
        }

        if (!string.IsNullOrWhiteSpace(options.Workspace))
        {
            args.Add("--workspace");
            args.Add(options.Workspace!);
        }

        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            args.Add("--container");
            args.Add(options.Container!);
        }

        if (options.Verbose)
        {
            args.Add("--verbose");
        }

        return nativeLifecycleRuntime.RunAsync(args, cancellationToken);
    }

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => acpProxyRunner.RunAsync(agent, cancellationToken);

    public Task<int> RunNativeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunAsync(args, cancellationToken);

    private static void AppendTokens(List<string> destination, IReadOnlyList<string> values)
    {
        foreach (var value in values)
        {
            destination.Add(value);
        }
    }

}
