using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportDirectoryManifestEntryImporter
{
    private readonly TextWriter stderr;
    private readonly IImportTransferOperations transferOperations;

    public ImportDirectoryManifestEntryImporter(
        TextWriter standardError,
        IImportTransferOperations importTransferOperations)
    {
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        transferOperations = importTransferOperations ?? throw new ArgumentNullException(nameof(importTransferOperations));
    }

    public async Task<int> ImportAsync(
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
}
