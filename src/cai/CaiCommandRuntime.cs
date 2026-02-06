using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly ILegacyContainAiBridge _legacyBridge;
    private readonly ICommandRuntimeService _runtimeService;
    private readonly AcpProxyRunner _acpProxyRunner;
    private readonly NativeLifecycleCommandRuntime _nativeLifecycleRuntime;
    private readonly TextWriter _stderr;

    public CaiCommandRuntime(
        ILegacyContainAiBridge legacyBridge,
        ICommandRuntimeService runtimeService,
        AcpProxyRunner acpProxyRunner,
        NativeLifecycleCommandRuntime? nativeLifecycleRuntime = null,
        TextWriter? stderr = null)
    {
        _legacyBridge = legacyBridge;
        _runtimeService = runtimeService;
        _acpProxyRunner = acpProxyRunner;
        _nativeLifecycleRuntime = nativeLifecycleRuntime ?? new NativeLifecycleCommandRuntime();
        _stderr = stderr ?? Console.Error;
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        if (!ShouldUseNativeRuntimeCore())
        {
            return _legacyBridge.InvokeAsync(BuildLegacyRunArgs(options), cancellationToken);
        }

        return _runtimeService.RunProcessAsync(RuntimeCoreCommandSpecFactory.CreateRunSpec(options), cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        if (!ShouldUseNativeRuntimeCore())
        {
            return _legacyBridge.InvokeAsync(BuildLegacyShellArgs(options), cancellationToken);
        }

        return _runtimeService.RunProcessAsync(RuntimeCoreCommandSpecFactory.CreateShellSpec(options), cancellationToken);
    }

    public async Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        if (!ShouldUseNativeRuntimeCore())
        {
            return await _legacyBridge.InvokeAsync(BuildLegacyExecArgs(options), cancellationToken).ConfigureAwait(false);
        }

        var spec = RuntimeCoreCommandSpecFactory.CreateExecSpec(options);
        if (spec.Arguments.Count == 0)
        {
            await _stderr.WriteLineAsync("exec requires a command or ssh target.").ConfigureAwait(false);
            return 2;
        }

        return await _runtimeService.RunProcessAsync(spec, cancellationToken).ConfigureAwait(false);
    }

    public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return _runtimeService.RunDockerAsync(RuntimeCoreCommandSpecFactory.CreateDockerSpec(options), cancellationToken);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        if (!ShouldUseNativeRuntimeCore())
        {
            return _legacyBridge.InvokeAsync(BuildLegacyStatusArgs(options), cancellationToken);
        }

        return _runtimeService.RunDockerAsync(RuntimeCoreCommandSpecFactory.CreateStatusSpec(options), cancellationToken);
    }

    public Task<int> RunLegacyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => _legacyBridge.InvokeAsync(args, cancellationToken);

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => _acpProxyRunner.RunAsync(agent, cancellationToken);

    public Task<int> RunNativeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => _nativeLifecycleRuntime.RunAsync(args, cancellationToken);

    private static bool ShouldUseNativeRuntimeCore()
        => string.Equals(Environment.GetEnvironmentVariable("CAI_NATIVE_RUNTIME_CORE"), "1", StringComparison.Ordinal);

    private static IReadOnlyList<string> BuildLegacyRunArgs(RunCommandOptions options)
    {
        var args = new List<string> { "run" };
        if (!string.IsNullOrWhiteSpace(options.Workspace))
        {
            args.Add("--workspace");
            args.Add(options.Workspace);
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

        args.AddRange(options.AdditionalArgs);
        args.AddRange(options.CommandArgs);
        return args;
    }

    private static IReadOnlyList<string> BuildLegacyShellArgs(ShellCommandOptions options)
    {
        var args = new List<string> { "shell" };
        if (!string.IsNullOrWhiteSpace(options.Workspace))
        {
            args.Add("--workspace");
            args.Add(options.Workspace);
        }

        if (options.Quiet)
        {
            args.Add("--quiet");
        }

        if (options.Verbose)
        {
            args.Add("--verbose");
        }

        args.AddRange(options.AdditionalArgs);
        args.AddRange(options.CommandArgs);
        return args;
    }

    private static IReadOnlyList<string> BuildLegacyExecArgs(ExecCommandOptions options)
    {
        var args = new List<string> { "exec" };
        if (!string.IsNullOrWhiteSpace(options.Workspace))
        {
            args.Add("--workspace");
            args.Add(options.Workspace);
        }

        if (options.Quiet)
        {
            args.Add("--quiet");
        }

        if (options.Verbose)
        {
            args.Add("--verbose");
        }

        args.AddRange(options.AdditionalArgs);
        args.AddRange(options.CommandArgs);
        return args;
    }

    private static IReadOnlyList<string> BuildLegacyStatusArgs(StatusCommandOptions options)
    {
        var args = new List<string> { "status" };
        if (options.Json)
        {
            args.Add("--json");
        }

        if (!string.IsNullOrWhiteSpace(options.Workspace))
        {
            args.Add("--workspace");
            args.Add(options.Workspace);
        }

        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            args.Add("--container");
            args.Add(options.Container);
        }

        if (options.Verbose)
        {
            args.Add("--verbose");
        }

        args.AddRange(options.AdditionalArgs);
        return args;
    }
}
