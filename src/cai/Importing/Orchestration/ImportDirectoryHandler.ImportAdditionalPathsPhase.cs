using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ImportDirectoryHandler
{
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
