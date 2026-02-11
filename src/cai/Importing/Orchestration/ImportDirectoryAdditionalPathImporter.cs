using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportDirectoryAdditionalPathImporter
{
    private readonly IImportPathOperations pathOperations;

    public ImportDirectoryAdditionalPathImporter(IImportPathOperations importPathOperations)
        => pathOperations = importPathOperations ?? throw new ArgumentNullException(nameof(importPathOperations));

    public async Task<int> ImportAsync(
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
