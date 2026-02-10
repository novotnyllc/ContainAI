using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportOrchestrationOperations
{
    private async Task<int> HandleArchiveImportAsync(
        ImportCommandOptions options,
        string sourcePath,
        string volume,
        bool excludePriv,
        IReadOnlyList<ManifestEntry> manifestEntries,
        CancellationToken cancellationToken)
    {
        if (!sourcePath.EndsWith(".tgz", StringComparison.OrdinalIgnoreCase))
        {
            await stderr.WriteLineAsync($"Unsupported import source file type: {sourcePath}").ConfigureAwait(false);
            return 1;
        }

        if (!options.DryRun)
        {
            var restoreCode = await transferOperations.RestoreArchiveImportAsync(volume, sourcePath, excludePriv, cancellationToken).ConfigureAwait(false);
            if (restoreCode != 0)
            {
                return restoreCode;
            }

            var applyOverrideCode = await transferOperations.ApplyImportOverridesAsync(
                volume,
                manifestEntries,
                options.NoSecrets,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (applyOverrideCode != 0)
            {
                return applyOverrideCode;
            }
        }

        await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> HandleDirectoryImportAsync(
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

        if (!options.DryRun)
        {
            var initCode = await transferOperations.InitializeImportTargetsAsync(
                volume,
                sourcePath,
                manifestEntries,
                options.NoSecrets,
                cancellationToken).ConfigureAwait(false);
            if (initCode != 0)
            {
                return initCode;
            }
        }

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

        if (!options.DryRun)
        {
            var secretPermissionsCode = await transferOperations.EnforceSecretPathPermissionsAsync(
                volume,
                manifestEntries,
                options.NoSecrets,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (secretPermissionsCode != 0)
            {
                return secretPermissionsCode;
            }
        }

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

    private static string ResolveDockerContextName()
    {
        var explicitContext = Environment.GetEnvironmentVariable("DOCKER_CONTEXT");
        if (!string.IsNullOrWhiteSpace(explicitContext))
        {
            return explicitContext;
        }

        return "default";
    }
}
