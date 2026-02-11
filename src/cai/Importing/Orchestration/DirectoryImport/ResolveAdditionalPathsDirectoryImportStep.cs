namespace ContainAI.Cli.Host;

internal sealed class ResolveAdditionalPathsDirectoryImportStep : IDirectoryImportStep
{
    private readonly ImportDirectoryAdditionalPathResolver additionalPathResolver;

    public ResolveAdditionalPathsDirectoryImportStep(ImportDirectoryAdditionalPathResolver importDirectoryAdditionalPathResolver)
        => additionalPathResolver = importDirectoryAdditionalPathResolver ?? throw new ArgumentNullException(nameof(importDirectoryAdditionalPathResolver));

    public async Task<int> ExecuteAsync(DirectoryImportContext context, CancellationToken cancellationToken)
    {
        var additionalImportPaths = await additionalPathResolver.ResolveAsync(
            context.Workspace,
            context.ExplicitConfigPath,
            context.ExcludePriv,
            context.SourcePath,
            context.Options.Verbose,
            cancellationToken).ConfigureAwait(false);
        context.SetAdditionalImportPaths(additionalImportPaths);
        return 0;
    }
}
