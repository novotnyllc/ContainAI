using ContainAI.Cli.Host.Importing.Symlinks;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestTransferOperations : CaiRuntimeSupport
    , IImportManifestTransferOperations
{
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportSymlinkRelinker symlinkRelinker;
    private readonly IImportManifestTargetInitializer targetInitializer;
    private readonly IImportManifestPlanBuilder planBuilder;
    private readonly IImportManifestCopyOperations copyOperations;

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
        : base(standardOutput, standardError)
        => (postCopyOperations, symlinkRelinker, targetInitializer, planBuilder, copyOperations) = (
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importSymlinkRelinker ?? throw new ArgumentNullException(nameof(importSymlinkRelinker)),
            importManifestTargetInitializer ?? throw new ArgumentNullException(nameof(importManifestTargetInitializer)),
            importManifestPlanBuilder ?? throw new ArgumentNullException(nameof(importManifestPlanBuilder)),
            importManifestCopyOperations ?? throw new ArgumentNullException(nameof(importManifestCopyOperations)));

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

        return await ApplyManifestPostCopyAsync(volume, entry, importPlan, dryRun, verbose, cancellationToken).ConfigureAwait(false);
    }

    public Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
        => postCopyOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);

    private async Task<int> ApplyManifestPostCopyAsync(
        string volume,
        ManifestEntry entry,
        ManifestImportPlan importPlan,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var postCopyCode = await postCopyOperations.ApplyManifestPostCopyRulesAsync(
            volume,
            entry,
            dryRun,
            verbose,
            cancellationToken).ConfigureAwait(false);
        if (postCopyCode != 0)
        {
            return postCopyCode;
        }

        if (!importPlan.IsDirectory)
        {
            return 0;
        }

        return await symlinkRelinker.RelinkImportedDirectorySymlinksAsync(
            volume,
            importPlan.SourceAbsolutePath,
            importPlan.NormalizedTarget,
            cancellationToken).ConfigureAwait(false);
    }
}
