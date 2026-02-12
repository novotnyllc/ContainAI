using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportSourceDispatcher : IImportSourceDispatcher
{
    private readonly ImportArchiveHandler archiveHandler;
    private readonly ImportDirectoryHandler directoryHandler;

    public ImportSourceDispatcher(ImportArchiveHandler importArchiveHandler, ImportDirectoryHandler importDirectoryHandler)
    {
        archiveHandler = importArchiveHandler ?? throw new ArgumentNullException(nameof(importArchiveHandler));
        directoryHandler = importDirectoryHandler ?? throw new ArgumentNullException(nameof(importDirectoryHandler));
    }

    public Task<int> DispatchAsync(
        ImportCommandOptions options,
        ImportRunContext context,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken)
        => File.Exists(context.SourcePath)
            ? archiveHandler.HandleArchiveImportAsync(
                options,
                context.SourcePath,
                context.Volume,
                context.ExcludePriv,
                manifestEntries,
                cancellationToken)
            : directoryHandler.HandleDirectoryImportAsync(
                options,
                context.Workspace,
                context.ExplicitConfigPath,
                context.SourcePath,
                context.Volume,
                context.ExcludePriv,
                manifestEntries,
                cancellationToken);
}
