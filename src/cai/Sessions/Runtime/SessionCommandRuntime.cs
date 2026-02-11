using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class SessionCommandRuntime
{
    private readonly ISessionOptionMapper optionMapper;
    private readonly ISessionCommandExecutionPipeline executionPipeline;

    public SessionCommandRuntime(TextWriter standardOutput, TextWriter standardError)
        : this(
            new SessionOptionMapper(),
            new SessionCommandExecutionPipeline(
                standardError,
                new SessionTargetResolver(),
                new SessionContainerProvisioner(standardError),
                new SessionRemoteExecutor(standardOutput, standardError, ConsoleInputState.Instance),
                new SessionStateStore(),
                new SessionDryRunReporter(standardOutput)))
    {
    }

    internal SessionCommandRuntime(
        ISessionOptionMapper sessionOptionMapper,
        ISessionCommandExecutionPipeline sessionCommandExecutionPipeline)
    {
        ArgumentNullException.ThrowIfNull(sessionOptionMapper);
        ArgumentNullException.ThrowIfNull(sessionCommandExecutionPipeline);

        optionMapper = sessionOptionMapper;
        executionPipeline = sessionCommandExecutionPipeline;
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return executionPipeline.RunAsync(optionMapper.FromRun(options), cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return executionPipeline.RunAsync(optionMapper.FromShell(options), cancellationToken);
    }

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return executionPipeline.RunAsync(optionMapper.FromExec(options), cancellationToken);
    }
}
