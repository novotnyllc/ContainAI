namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportManifestTransferOperations
{
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
}
