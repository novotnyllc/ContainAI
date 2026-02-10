using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ImportDirectoryHandler
{
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
}
