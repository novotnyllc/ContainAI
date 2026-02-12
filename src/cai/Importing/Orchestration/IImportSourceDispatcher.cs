using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IImportSourceDispatcher
{
    Task<int> DispatchAsync(
        ImportCommandOptions options,
        ImportRunContext context,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken);
}
