using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class SessionCommandRuntime
{
    private readonly TextWriter stderr;
    private readonly ISessionTargetResolver targetResolver;
    private readonly ISessionOptionMapper optionMapper;
    private readonly SessionContainerProvisioner containerProvisioner;
    private readonly SessionRemoteExecutor remoteExecutor;
    private readonly SessionStateStore stateStore;
    private readonly SessionDryRunReporter dryRunReporter;

    public SessionCommandRuntime(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardError,
            new SessionTargetResolver(),
            new SessionOptionMapper(),
            new SessionContainerProvisioner(standardError),
            new SessionRemoteExecutor(standardOutput, standardError, ConsoleInputState.Instance),
            new SessionStateStore(),
            new SessionDryRunReporter(standardOutput))
    {
    }

    internal SessionCommandRuntime(
        TextWriter standardError,
        ISessionTargetResolver sessionTargetResolver,
        ISessionOptionMapper sessionOptionMapper,
        SessionContainerProvisioner sessionContainerProvisioner,
        SessionRemoteExecutor sessionRemoteExecutor,
        SessionStateStore sessionStateStore,
        SessionDryRunReporter sessionDryRunReporter)
    {
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(sessionTargetResolver);
        ArgumentNullException.ThrowIfNull(sessionOptionMapper);
        ArgumentNullException.ThrowIfNull(sessionContainerProvisioner);
        ArgumentNullException.ThrowIfNull(sessionRemoteExecutor);
        ArgumentNullException.ThrowIfNull(sessionStateStore);
        ArgumentNullException.ThrowIfNull(sessionDryRunReporter);

        stderr = standardError;
        targetResolver = sessionTargetResolver;
        optionMapper = sessionOptionMapper;
        containerProvisioner = sessionContainerProvisioner;
        remoteExecutor = sessionRemoteExecutor;
        stateStore = sessionStateStore;
        dryRunReporter = sessionDryRunReporter;
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunSessionAsync(optionMapper.FromRun(options), cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunSessionAsync(optionMapper.FromShell(options), cancellationToken);
    }

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunSessionAsync(optionMapper.FromExec(options), cancellationToken);
    }
}
