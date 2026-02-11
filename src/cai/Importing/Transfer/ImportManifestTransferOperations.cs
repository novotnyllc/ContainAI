using ContainAI.Cli.Host.Importing.Symlinks;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestTransferOperations : IImportManifestTransferOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportManifestTargetInitializer targetInitializer;
    private readonly IImportManifestPlanBuilder planBuilder;
    private readonly IImportManifestCopyOperations copyOperations;
    private readonly IImportManifestPostCopyTransferOperations postCopyTransferOperations;

    public ImportManifestTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new CaiImportPostCopyOperations(standardOutput, standardError),
            new ImportSymlinkRelinker(standardOutput, standardError),
            new ImportManifestTargetInitializer(standardOutput, standardError),
            new ImportManifestPlanBuilder(),
            new ImportManifestCopyOperations(standardOutput, standardError))
    {
    }

    internal ImportManifestTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker,
        IImportManifestTargetInitializer importManifestTargetInitializer,
        IImportManifestPlanBuilder importManifestPlanBuilder,
        IImportManifestCopyOperations importManifestCopyOperations)
        : this(
            standardOutput,
            standardError,
            importPostCopyOperations,
            importManifestTargetInitializer,
            importManifestPlanBuilder,
            importManifestCopyOperations,
            CreatePostCopyTransferOperations(importPostCopyOperations, importSymlinkRelinker))
    {
    }

    internal ImportManifestTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPostCopyOperations importPostCopyOperations,
        IImportManifestTargetInitializer importManifestTargetInitializer,
        IImportManifestPlanBuilder importManifestPlanBuilder,
        IImportManifestCopyOperations importManifestCopyOperations,
        IImportManifestPostCopyTransferOperations importManifestPostCopyTransferOperations)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        (postCopyOperations, targetInitializer, planBuilder, copyOperations, postCopyTransferOperations) = (
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importManifestTargetInitializer ?? throw new ArgumentNullException(nameof(importManifestTargetInitializer)),
            importManifestPlanBuilder ?? throw new ArgumentNullException(nameof(importManifestPlanBuilder)),
            importManifestCopyOperations ?? throw new ArgumentNullException(nameof(importManifestCopyOperations)),
            importManifestPostCopyTransferOperations ?? throw new ArgumentNullException(nameof(importManifestPostCopyTransferOperations)));
    }

    public async Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        foreach (var entry in entries)
        {
            var ensureCode = await targetInitializer.EnsureEntryTargetAsync(
                volume,
                sourceRoot,
                entry,
                noSecrets,
                cancellationToken).ConfigureAwait(false);
            if (ensureCode != 0)
            {
                return ensureCode;
            }
        }

        return 0;
    }

    public async Task<int> ImportManifestEntryAsync(
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

    public Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
        => postCopyOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);

    private static ImportManifestPostCopyTransferOperations CreatePostCopyTransferOperations(
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker)
        => new ImportManifestPostCopyTransferOperations(
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importSymlinkRelinker ?? throw new ArgumentNullException(nameof(importSymlinkRelinker)));
}
