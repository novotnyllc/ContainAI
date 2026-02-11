namespace ContainAI.Cli.Host;

internal sealed class InitializeTargetDirectoryImportStep : IDirectoryImportStep
{
    private readonly ImportDirectoryTargetInitializer targetInitializer;

    public InitializeTargetDirectoryImportStep(ImportDirectoryTargetInitializer importDirectoryTargetInitializer)
        => targetInitializer = importDirectoryTargetInitializer ?? throw new ArgumentNullException(nameof(importDirectoryTargetInitializer));

    public Task<int> ExecuteAsync(DirectoryImportContext context, CancellationToken cancellationToken)
        => targetInitializer.InitializeIfNeededAsync(
            context.Options,
            context.Volume,
            context.SourcePath,
            context.ManifestEntries,
            cancellationToken);
}
