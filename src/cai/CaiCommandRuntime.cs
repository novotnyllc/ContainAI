using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly ICommandRuntimeService _runtimeService;
    private readonly AcpProxyRunner _acpProxyRunner;
    private readonly NativeLifecycleCommandRuntime _nativeLifecycleRuntime;
    private readonly TextWriter _stderr;

    public CaiCommandRuntime(
        ICommandRuntimeService runtimeService,
        AcpProxyRunner acpProxyRunner,
        NativeLifecycleCommandRuntime? nativeLifecycleRuntime = null,
        TextWriter? stderr = null)
    {
        _runtimeService = runtimeService;
        _acpProxyRunner = acpProxyRunner;
        _nativeLifecycleRuntime = nativeLifecycleRuntime ?? new NativeLifecycleCommandRuntime();
        _stderr = stderr ?? Console.Error;
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return _runtimeService.RunProcessAsync(RuntimeCoreCommandSpecFactory.CreateRunSpec(options), cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return _runtimeService.RunProcessAsync(RuntimeCoreCommandSpecFactory.CreateShellSpec(options), cancellationToken);
    }

    public async Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

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
        return _runtimeService.RunDockerAsync(RuntimeCoreCommandSpecFactory.CreateStatusSpec(options), cancellationToken);
    }

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => _acpProxyRunner.RunAsync(agent, cancellationToken);

    public Task<int> RunNativeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => _nativeLifecycleRuntime.RunAsync(args, cancellationToken);
}
