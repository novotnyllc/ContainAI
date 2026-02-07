using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly AcpProxyRunner _acpProxyRunner;
    private readonly NativeLifecycleCommandRuntime _nativeLifecycleRuntime;

    public CaiCommandRuntime(
        AcpProxyRunner acpProxyRunner,
        NativeLifecycleCommandRuntime? nativeLifecycleRuntime = null)
    {
        _acpProxyRunner = acpProxyRunner;
        _nativeLifecycleRuntime = nativeLifecycleRuntime ?? new NativeLifecycleCommandRuntime();
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return _nativeLifecycleRuntime.RunAsync(BuildRunArgs(options), cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return _nativeLifecycleRuntime.RunAsync(BuildShellArgs(options), cancellationToken);
    }

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return _nativeLifecycleRuntime.RunAsync(BuildExecArgs(options), cancellationToken);
    }

    public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>
        {
            "docker",
        };

        AppendTokens(args, options.DockerArgs);
        return _nativeLifecycleRuntime.RunAsync(args, cancellationToken);
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

        AppendTokens(args, options.AdditionalArgs);
        return _nativeLifecycleRuntime.RunAsync(args, cancellationToken);
    }

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => _acpProxyRunner.RunAsync(agent, cancellationToken);

    public Task<int> RunNativeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => _nativeLifecycleRuntime.RunAsync(args, cancellationToken);

    private static IReadOnlyList<string> BuildRunArgs(RunCommandOptions options)
    {
        var args = new List<string>
        {
            "run",
        };

        if (!string.IsNullOrWhiteSpace(options.Workspace))
        {
            args.Add("--workspace");
            args.Add(options.Workspace!);
        }

        if (options.Fresh)
        {
            args.Add("--fresh");
        }

        if (options.Detached)
        {
            args.Add("--detached");
        }

        if (options.Quiet)
        {
            args.Add("--quiet");
        }

        if (options.Verbose)
        {
            args.Add("--verbose");
        }

        AppendTokens(args, options.AdditionalArgs);
        if (options.CommandArgs.Count > 0)
        {
            args.Add("--");
            AppendTokens(args, options.CommandArgs);
        }

        return args;
    }

    private static IReadOnlyList<string> BuildShellArgs(ShellCommandOptions options)
    {
        var args = new List<string>
        {
            "shell",
        };

        if (!string.IsNullOrWhiteSpace(options.Workspace))
        {
            args.Add("--workspace");
            args.Add(options.Workspace!);
        }

        if (options.Quiet)
        {
            args.Add("--quiet");
        }

        if (options.Verbose)
        {
            args.Add("--verbose");
        }

        AppendTokens(args, options.AdditionalArgs);
        AppendTokens(args, options.CommandArgs);
        return args;
    }

    private static IReadOnlyList<string> BuildExecArgs(ExecCommandOptions options)
    {
        var args = new List<string>
        {
            "exec",
        };

        if (!string.IsNullOrWhiteSpace(options.Workspace))
        {
            args.Add("--workspace");
            args.Add(options.Workspace!);
        }

        if (options.Quiet)
        {
            args.Add("--quiet");
        }

        if (options.Verbose)
        {
            args.Add("--verbose");
        }

        AppendTokens(args, options.AdditionalArgs);
        AppendTokens(args, options.CommandArgs);
        return args;
    }

    private static void AppendTokens(List<string> destination, IReadOnlyList<string> values)
    {
        foreach (var value in values)
        {
            destination.Add(value);
        }
    }
}
