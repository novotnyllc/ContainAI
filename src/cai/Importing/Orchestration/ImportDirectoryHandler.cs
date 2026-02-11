using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportDirectoryHandler
{
    private readonly TextWriter stdout;
    private readonly DirectoryImportStepRunner stepRunner;

    public ImportDirectoryHandler(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPathOperations pathOperations,
        IImportTransferOperations transferOperations,
        IImportEnvironmentOperations environmentOperations)
        : this(
            standardOutput,
            standardError,
            new ImportDirectoryAdditionalPathResolver(pathOperations),
            new ImportDirectoryTargetInitializer(transferOperations),
            new ImportDirectoryManifestEntryImporter(standardError, transferOperations),
            new ImportDirectorySecretPermissionsEnforcer(transferOperations),
            new ImportDirectoryAdditionalPathImporter(pathOperations),
            environmentOperations,
            new ImportDirectoryOverridesApplier(transferOperations))
    {
    }

    internal ImportDirectoryHandler(
        TextWriter standardOutput,
        TextWriter standardError,
        ImportDirectoryAdditionalPathResolver importDirectoryAdditionalPathResolver,
        ImportDirectoryTargetInitializer importDirectoryTargetInitializer,
        ImportDirectoryManifestEntryImporter importDirectoryManifestEntryImporter,
        ImportDirectorySecretPermissionsEnforcer importDirectorySecretPermissionsEnforcer,
        ImportDirectoryAdditionalPathImporter importDirectoryAdditionalPathImporter,
        IImportEnvironmentOperations importEnvironmentOperations,
        ImportDirectoryOverridesApplier importDirectoryOverridesApplier)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        _ = standardError ?? throw new ArgumentNullException(nameof(standardError));
        var additionalPathResolver = importDirectoryAdditionalPathResolver ?? throw new ArgumentNullException(nameof(importDirectoryAdditionalPathResolver));
        var targetInitializer = importDirectoryTargetInitializer ?? throw new ArgumentNullException(nameof(importDirectoryTargetInitializer));
        var manifestEntryImporter = importDirectoryManifestEntryImporter ?? throw new ArgumentNullException(nameof(importDirectoryManifestEntryImporter));
        var secretPermissionsEnforcer = importDirectorySecretPermissionsEnforcer ?? throw new ArgumentNullException(nameof(importDirectorySecretPermissionsEnforcer));
        var additionalPathImporter = importDirectoryAdditionalPathImporter ?? throw new ArgumentNullException(nameof(importDirectoryAdditionalPathImporter));
        var environmentOperations = importEnvironmentOperations ?? throw new ArgumentNullException(nameof(importEnvironmentOperations));
        var overridesApplier = importDirectoryOverridesApplier ?? throw new ArgumentNullException(nameof(importDirectoryOverridesApplier));

        stepRunner = new DirectoryImportStepRunner(
            new IDirectoryImportStep[]
            {
                new ResolveAdditionalPathsDirectoryImportStep(additionalPathResolver),
                new InitializeTargetDirectoryImportStep(targetInitializer),
                new ImportManifestEntriesDirectoryImportStep(manifestEntryImporter),
                new EnforceSecretPermissionsDirectoryImportStep(secretPermissionsEnforcer),
                new ImportAdditionalPathsDirectoryImportStep(additionalPathImporter),
                new ImportEnvironmentVariablesDirectoryImportStep(environmentOperations),
                new ApplyOverridesDirectoryImportStep(overridesApplier),
            });
    }

    public async Task<int> HandleDirectoryImportAsync(
        ImportCommandOptions options,
        string workspace,
        string? explicitConfigPath,
        string sourcePath,
        string volume,
        bool excludePriv,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken)
    {
        var context = new DirectoryImportContext(
            options,
            workspace,
            explicitConfigPath,
            sourcePath,
            volume,
            excludePriv,
            manifestEntries);
        var importCode = await stepRunner.RunAsync(context, cancellationToken).ConfigureAwait(false);
        if (importCode != 0)
        {
            return importCode;
        }

        await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }
}
