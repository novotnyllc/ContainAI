namespace ContainAI.Cli.Host;

internal interface ISessionCommandExecutionPipeline
{
    Task<int> RunAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class SessionCommandExecutionPipeline(
    TextWriter stderr,
    ISessionTargetResolver targetResolver,
    SessionContainerProvisioner containerProvisioner,
    SessionRemoteExecutor remoteExecutor,
    SessionStateStore stateStore,
    SessionDryRunReporter dryRunReporter) : ISessionCommandExecutionPipeline
{
    public async Task<int> RunAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var resolved = await targetResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
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
