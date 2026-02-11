namespace ContainAI.Cli.Host;

internal sealed class ApplyOverridesDirectoryImportStep : IDirectoryImportStep
{
    private readonly ImportDirectoryOverridesApplier overridesApplier;

    public ApplyOverridesDirectoryImportStep(ImportDirectoryOverridesApplier importDirectoryOverridesApplier)
        => overridesApplier = importDirectoryOverridesApplier ?? throw new ArgumentNullException(nameof(importDirectoryOverridesApplier));

    public Task<int> ExecuteAsync(DirectoryImportContext context, CancellationToken cancellationToken)
        => overridesApplier.ApplyAsync(
            context.Options,
            context.Volume,
            context.ManifestEntries,
            cancellationToken);
}
