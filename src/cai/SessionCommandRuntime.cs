using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class SessionCommandRuntime
{
    private readonly TextWriter stderr;
    private readonly SessionContainerProvisioner containerProvisioner;
    private readonly SessionRemoteExecutor remoteExecutor;
    private readonly SessionStateStore stateStore;
    private readonly SessionDryRunReporter dryRunReporter;

    public SessionCommandRuntime(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardError,
            new SessionContainerProvisioner(standardError),
            new SessionRemoteExecutor(standardOutput, standardError, ConsoleInputState.Instance),
            new SessionStateStore(),
            new SessionDryRunReporter(standardOutput))
    {
    }

    internal SessionCommandRuntime(
        TextWriter standardError,
        SessionContainerProvisioner sessionContainerProvisioner,
        SessionRemoteExecutor sessionRemoteExecutor,
        SessionStateStore sessionStateStore,
        SessionDryRunReporter sessionDryRunReporter)
    {
        stderr = standardError;
        containerProvisioner = sessionContainerProvisioner;
        remoteExecutor = sessionRemoteExecutor;
        stateStore = sessionStateStore;
        dryRunReporter = sessionDryRunReporter;
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunSessionAsync(SessionOptionMapper.FromRun(options), cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunSessionAsync(SessionOptionMapper.FromShell(options), cancellationToken);
    }

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunSessionAsync(SessionOptionMapper.FromExec(options), cancellationToken);
    }

    private async Task<int> RunSessionAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var resolved = await SessionTargetResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(resolved.Error))
        {
            await stderr.WriteLineAsync(resolved.Error).ConfigureAwait(false);
            return resolved.ErrorCode;
        }

        var effectiveOptions = resolved.GeneratedFromReset
            ? options with { Fresh = true }
            : options;

        if (options.DryRun)
        {
            await dryRunReporter.WriteAsync(effectiveOptions, resolved, cancellationToken).ConfigureAwait(false);
            return 0;
        }

        var ensured = await containerProvisioner.EnsureAsync(effectiveOptions, resolved, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(ensured.Error))
        {
            await stderr.WriteLineAsync(ensured.Error).ConfigureAwait(false);
            return ensured.ErrorCode;
        }

        if (resolved.ShouldPersistState)
        {
            await stateStore.PersistAsync(ensured, cancellationToken).ConfigureAwait(false);
        }

        return await remoteExecutor.ExecuteAsync(effectiveOptions, ensured, cancellationToken).ConfigureAwait(false);
    }
}
