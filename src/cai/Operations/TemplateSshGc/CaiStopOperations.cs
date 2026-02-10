namespace ContainAI.Cli.Host;

internal sealed partial class CaiStopOperations : CaiRuntimeSupport
{
    private readonly Func<string?, string?, string?, string?, CancellationToken, Task<int>> runExportAsync;

    public CaiStopOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<string?, string?, string?, string?, CancellationToken, Task<int>> runExportAsync)
        : base(standardOutput, standardError)
        => this.runExportAsync = runExportAsync ?? throw new ArgumentNullException(nameof(runExportAsync));

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

        var targets = await ResolveStopTargetsAsync(containerName, stopAll, cancellationToken).ConfigureAwait(false);
        if (targets is null)
        {
            return 1;
        }

        if (targets.Count == 0)
        {
            await stdout.WriteLineAsync("No ContainAI containers found.").ConfigureAwait(false);
            return 0;
        }

        var failures = await StopTargetsAsync(targets, remove, force, exportFirst, cancellationToken).ConfigureAwait(false);
        return failures == 0 ? 0 : 1;
    }
}
