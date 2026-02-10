using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ImportDirectoryHandler : CaiRuntimeSupport
{
    private readonly IImportPathOperations pathOperations;
    private readonly IImportTransferOperations transferOperations;
    private readonly IImportEnvironmentOperations environmentOperations;

    public ImportDirectoryHandler(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPathOperations pathOperations,
        IImportTransferOperations transferOperations,
        IImportEnvironmentOperations environmentOperations)
        : base(standardOutput, standardError)
    {
        this.pathOperations = pathOperations ?? throw new ArgumentNullException(nameof(pathOperations));
        this.transferOperations = transferOperations ?? throw new ArgumentNullException(nameof(transferOperations));
        this.environmentOperations = environmentOperations ?? throw new ArgumentNullException(nameof(environmentOperations));
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
        var additionalImportPaths = await pathOperations.ResolveAdditionalImportPathsAsync(
            workspace,
            explicitConfigPath,
            excludePriv,
            sourcePath,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);

        var initCode = await InitializeTargetsIfNeededAsync(options, volume, sourcePath, manifestEntries, cancellationToken).ConfigureAwait(false);
        if (initCode != 0)
        {
            return initCode;
        }

        var manifestImportCode = await ImportManifestEntriesAsync(options, volume, sourcePath, excludePriv, manifestEntries, cancellationToken).ConfigureAwait(false);
        if (manifestImportCode != 0)
        {
            return manifestImportCode;
        }

        var secretPermissionsCode = await EnforceSecretPermissionsIfNeededAsync(options, volume, manifestEntries, cancellationToken).ConfigureAwait(false);
        if (secretPermissionsCode != 0)
        {
            return secretPermissionsCode;
        }

        var additionalPathImportCode = await ImportAdditionalPathsAsync(options, volume, additionalImportPaths, cancellationToken).ConfigureAwait(false);
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

        var overrideCode = await transferOperations.ApplyImportOverridesAsync(
            volume,
            manifestEntries,
            options.NoSecrets,
            options.DryRun,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
        if (overrideCode != 0)
        {
            return overrideCode;
        }

        await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }
}
