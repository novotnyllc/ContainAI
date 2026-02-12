using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface IImportGitConfigFilterOperations
{
    Task<int> ApplyGitConfigFilterAsync(
        string volume,
        string targetRelativePath,
        bool verbose,
        CancellationToken cancellationToken);
}
