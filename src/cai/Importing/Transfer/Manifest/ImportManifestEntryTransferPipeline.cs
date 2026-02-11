namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestEntryTransferPipeline
{
    Task<int> ImportAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}

internal sealed class ImportManifestEntryTransferPipeline : IImportManifestEntryTransferPipeline
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IImportManifestPlanBuilder planBuilder;
    private readonly IImportManifestCopyOperations copyOperations;
    private readonly IImportManifestPostCopyTransferOperations postCopyTransferOperations;

    public ImportManifestEntryTransferPipeline(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportManifestPlanBuilder importManifestPlanBuilder,
        IImportManifestCopyOperations importManifestCopyOperations,
        IImportManifestPostCopyTransferOperations importManifestPostCopyTransferOperations)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        (planBuilder, copyOperations, postCopyTransferOperations) = (
            importManifestPlanBuilder ?? throw new ArgumentNullException(nameof(importManifestPlanBuilder)),
            importManifestCopyOperations ?? throw new ArgumentNullException(nameof(importManifestCopyOperations)),
            importManifestPostCopyTransferOperations ?? throw new ArgumentNullException(nameof(importManifestPostCopyTransferOperations)));
    }

    public async Task<int> ImportAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var importPlan = planBuilder.Create(sourceRoot, entry);
        if (!importPlan.SourceExists)
        {
            if (verbose && !entry.Optional)
            {
                await stderr.WriteLineAsync($"Source not found: {entry.Source}").ConfigureAwait(false);
            }

            return 0;
        }

        if (dryRun)
        {
            await stdout.WriteLineAsync($"[DRY-RUN] Would sync {entry.Source} -> {entry.Target}").ConfigureAwait(false);
            return 0;
        }

        var copyCode = await copyOperations.CopyManifestEntryAsync(
            volume,
            sourceRoot,
            entry,
            excludePriv,
            noExcludes,
            importPlan,
            cancellationToken).ConfigureAwait(false);
        if (copyCode != 0)
        {
            return copyCode;
        }

        return await postCopyTransferOperations.ApplyManifestPostCopyAsync(
            volume,
            entry,
            importPlan,
            dryRun,
            verbose,
            cancellationToken).ConfigureAwait(false);
    }
}
