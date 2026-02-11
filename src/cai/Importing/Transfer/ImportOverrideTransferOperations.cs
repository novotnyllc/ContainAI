namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportOverrideTransferOperations : IImportOverrideTransferOperations
{
    private readonly TextWriter stdout;
    private readonly ImportOverridePreparationService preparationService;
    private readonly ImportOverrideCopyExecutor copyExecutor;

    public ImportOverrideTransferOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        preparationService = new ImportOverridePreparationService(standardError);
        copyExecutor = new ImportOverrideCopyExecutor(standardError);
    }

    public async Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var overridesDirectory = ImportOverrideFileCatalog.ResolveOverridesDirectory();
        if (!Directory.Exists(overridesDirectory))
        {
            return 0;
        }

        foreach (var file in ImportOverrideFileCatalog.GetOverrideFiles(overridesDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();

            var preparedOverride = await preparationService
                .PrepareAsync(overridesDirectory, file, manifestEntries, noSecrets, verbose)
                .ConfigureAwait(false);

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

            var copyCode = await copyExecutor
                .CopyAsync(volume, overridesDirectory, preparedOverride.Value, cancellationToken)
                .ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        return 0;
    }
}
