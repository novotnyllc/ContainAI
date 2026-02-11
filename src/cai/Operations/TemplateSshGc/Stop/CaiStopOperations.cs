namespace ContainAI.Cli.Host;

internal sealed class CaiStopOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly ICaiStopTargetResolver targetResolver;
    private readonly ICaiStopTargetExecutor targetExecutor;

    public CaiStopOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<string?, string?, string?, string?, CancellationToken, Task<int>> runExportAsync)
        : this(
            standardOutput,
            standardError,
            new CaiStopTargetResolver(standardError),
            new CaiStopTargetExecutor(standardError, runExportAsync))
    {
    }

    internal CaiStopOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ICaiStopTargetResolver caiStopTargetResolver,
        ICaiStopTargetExecutor caiStopTargetExecutor)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        targetResolver = caiStopTargetResolver ?? throw new ArgumentNullException(nameof(caiStopTargetResolver));
        targetExecutor = caiStopTargetExecutor ?? throw new ArgumentNullException(nameof(caiStopTargetExecutor));
    }

    public async Task<int> RunStopAsync(
        string? containerName,
        bool stopAll,
        bool remove,
        bool force,
        bool exportFirst,
        CancellationToken cancellationToken)
    {
        if (stopAll && !string.IsNullOrWhiteSpace(containerName))
        {
            await stderr.WriteLineAsync("--all and --container are mutually exclusive").ConfigureAwait(false);
            return 1;
        }

        if (stopAll && exportFirst)
        {
            await stderr.WriteLineAsync("--export and --all are mutually exclusive").ConfigureAwait(false);
            return 1;
        }

        var targetResolution = await targetResolver.ResolveAsync(containerName, stopAll, cancellationToken).ConfigureAwait(false);
        if (!targetResolution.Success)
        {
            return 1;
        }

        var targets = targetResolution.Value!;
        if (targets.Count == 0)
        {
            await stdout.WriteLineAsync("No ContainAI containers found.").ConfigureAwait(false);
            return 0;
        }

        var failures = await targetExecutor.ExecuteAsync(targets, remove, force, exportFirst, cancellationToken).ConfigureAwait(false);
        return failures == 0 ? 0 : 1;
    }
}
