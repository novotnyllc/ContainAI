using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ImportDirectoryHandler
{
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
}
