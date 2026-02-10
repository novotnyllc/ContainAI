namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportOverrideTransferOperations
{
    public async Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var overridesDirectory = Path.Combine(ResolveHomeDirectory(), ".config", "containai", "import-overrides");
        if (!Directory.Exists(overridesDirectory))
        {
            return 0;
        }

        var overrideFiles = GetOverrideFiles(overridesDirectory);
        foreach (var file in overrideFiles)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var preparedOverride = await PrepareOverrideFileAsync(
                overridesDirectory,
                file,
                manifestEntries,
                noSecrets,
                verbose).ConfigureAwait(false);
            if (preparedOverride is null)
            {
                continue;
            }

            if (dryRun)
            {
                await stdout.WriteLineAsync(
                    $"[DRY-RUN] Would apply override {preparedOverride.Value.RelativePath} -> {preparedOverride.Value.MappedTargetPath}")
                    .ConfigureAwait(false);
                continue;
            }

            var copyCode = await CopyPreparedOverrideAsync(
                volume,
                overridesDirectory,
                preparedOverride.Value,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        return 0;
    }
}
