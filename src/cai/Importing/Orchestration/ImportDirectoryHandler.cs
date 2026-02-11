using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportDirectoryHandler
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IImportPathOperations pathOperations;
    private readonly IImportTransferOperations transferOperations;
    private readonly IImportEnvironmentOperations environmentOperations;

    public ImportDirectoryHandler(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPathOperations pathOperations,
        IImportTransferOperations transferOperations,
        IImportEnvironmentOperations environmentOperations)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
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

    private async Task<int> InitializeTargetsIfNeededAsync(
        ImportCommandOptions options,
        string volume,
        string sourcePath,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken)
    {
        if (options.DryRun)
        {
            return 0;
        }

        return await transferOperations.InitializeImportTargetsAsync(
            volume,
            sourcePath,
            manifestEntries,
            options.NoSecrets,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> ImportManifestEntriesAsync(
        ImportCommandOptions options,
        string volume,
        string sourcePath,
        bool excludePriv,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken)
    {
        foreach (var entry in manifestEntries)
        {
            if (options.NoSecrets && entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                if (options.Verbose)
                {
                    await stderr.WriteLineAsync($"Skipping secret entry: {entry.Source}").ConfigureAwait(false);
                }

                continue;
            }

            var copyCode = await transferOperations.ImportManifestEntryAsync(
                volume,
                sourcePath,
                entry,
                excludePriv,
                options.NoExcludes,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        return 0;
    }

    private async Task<int> EnforceSecretPermissionsIfNeededAsync(
        ImportCommandOptions options,
        string volume,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken)
    {
        if (options.DryRun)
        {
            return 0;
        }

        return await transferOperations.EnforceSecretPathPermissionsAsync(
            volume,
            manifestEntries,
            options.NoSecrets,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> ImportAdditionalPathsAsync(
        ImportCommandOptions options,
        string volume,
        IReadOnlyList<ImportAdditionalPath> additionalImportPaths,
        CancellationToken cancellationToken)
    {
        foreach (var additionalPath in additionalImportPaths)
        {
            var copyCode = await pathOperations.ImportAdditionalPathAsync(
                volume,
                additionalPath,
                options.NoExcludes,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        return 0;
    }
}
