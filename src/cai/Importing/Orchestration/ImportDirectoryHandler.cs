using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportDirectoryHandler
{
    private readonly TextWriter stdout;
    private readonly ImportDirectoryAdditionalPathResolver additionalPathResolver;
    private readonly ImportDirectoryTargetInitializer targetInitializer;
    private readonly ImportDirectoryManifestEntryImporter manifestEntryImporter;
    private readonly ImportDirectorySecretPermissionsEnforcer secretPermissionsEnforcer;
    private readonly ImportDirectoryAdditionalPathImporter additionalPathImporter;
    private readonly IImportEnvironmentOperations environmentOperations;
    private readonly ImportDirectoryOverridesApplier overridesApplier;

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
        additionalPathResolver = importDirectoryAdditionalPathResolver ?? throw new ArgumentNullException(nameof(importDirectoryAdditionalPathResolver));
        targetInitializer = importDirectoryTargetInitializer ?? throw new ArgumentNullException(nameof(importDirectoryTargetInitializer));
        manifestEntryImporter = importDirectoryManifestEntryImporter ?? throw new ArgumentNullException(nameof(importDirectoryManifestEntryImporter));
        secretPermissionsEnforcer = importDirectorySecretPermissionsEnforcer ?? throw new ArgumentNullException(nameof(importDirectorySecretPermissionsEnforcer));
        additionalPathImporter = importDirectoryAdditionalPathImporter ?? throw new ArgumentNullException(nameof(importDirectoryAdditionalPathImporter));
        environmentOperations = importEnvironmentOperations ?? throw new ArgumentNullException(nameof(importEnvironmentOperations));
        overridesApplier = importDirectoryOverridesApplier ?? throw new ArgumentNullException(nameof(importDirectoryOverridesApplier));
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
        var additionalImportPaths = await additionalPathResolver.ResolveAsync(
            workspace,
            explicitConfigPath,
            excludePriv,
            sourcePath,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);

        var initCode = await targetInitializer
            .InitializeIfNeededAsync(options, volume, sourcePath, manifestEntries, cancellationToken)
            .ConfigureAwait(false);
        if (initCode != 0)
        {
            return initCode;
        }

        var manifestImportCode = await manifestEntryImporter
            .ImportAsync(options, volume, sourcePath, excludePriv, manifestEntries, cancellationToken)
            .ConfigureAwait(false);
        if (manifestImportCode != 0)
        {
            return manifestImportCode;
        }

        var secretPermissionsCode = await secretPermissionsEnforcer
            .EnforceIfNeededAsync(options, volume, manifestEntries, cancellationToken)
            .ConfigureAwait(false);
        if (secretPermissionsCode != 0)
        {
            return secretPermissionsCode;
        }

        var additionalPathImportCode = await additionalPathImporter
            .ImportAsync(options, volume, additionalImportPaths, cancellationToken)
            .ConfigureAwait(false);
        if (additionalPathImportCode != 0)
        {
            return additionalPathImportCode;
        }

        var environmentCode = await environmentOperations.ImportEnvironmentVariablesAsync(
            volume,
            workspace,
            explicitConfigPath,
            options.DryRun,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
        if (environmentCode != 0)
        {
            return environmentCode;
        }

        var overrideCode = await overridesApplier
            .ApplyAsync(options, volume, manifestEntries, cancellationToken)
            .ConfigureAwait(false);
        if (overrideCode != 0)
        {
            return overrideCode;
        }

        await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }
}
