namespace ContainAI.Cli.Host;

internal sealed class ImportAdditionalPathsDirectoryImportStep : IDirectoryImportStep
{
    private readonly ImportDirectoryAdditionalPathImporter additionalPathImporter;

    public ImportAdditionalPathsDirectoryImportStep(ImportDirectoryAdditionalPathImporter importDirectoryAdditionalPathImporter)
        => additionalPathImporter = importDirectoryAdditionalPathImporter ?? throw new ArgumentNullException(nameof(importDirectoryAdditionalPathImporter));

    public Task<int> ExecuteAsync(DirectoryImportContext context, CancellationToken cancellationToken)
        => additionalPathImporter.ImportAsync(
            context.Options,
            context.Volume,
            context.AdditionalImportPaths,
            cancellationToken);
}
