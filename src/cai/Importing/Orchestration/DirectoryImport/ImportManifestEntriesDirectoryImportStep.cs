namespace ContainAI.Cli.Host;

internal sealed class ImportManifestEntriesDirectoryImportStep : IDirectoryImportStep
{
    private readonly ImportDirectoryManifestEntryImporter manifestEntryImporter;

    public ImportManifestEntriesDirectoryImportStep(ImportDirectoryManifestEntryImporter importDirectoryManifestEntryImporter)
        => manifestEntryImporter = importDirectoryManifestEntryImporter ?? throw new ArgumentNullException(nameof(importDirectoryManifestEntryImporter));

    public Task<int> ExecuteAsync(DirectoryImportContext context, CancellationToken cancellationToken)
        => manifestEntryImporter.ImportAsync(
            context.Options,
            context.Volume,
            context.SourcePath,
            context.ExcludePriv,
            context.ManifestEntries,
            cancellationToken);
}
