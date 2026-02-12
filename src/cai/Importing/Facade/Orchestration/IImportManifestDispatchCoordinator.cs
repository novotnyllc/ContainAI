using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IImportManifestDispatchCoordinator
{
    Task<int> ExecuteAsync(
        ImportCommandOptions options,
        ImportRunContext context,
        CancellationToken cancellationToken);
}
