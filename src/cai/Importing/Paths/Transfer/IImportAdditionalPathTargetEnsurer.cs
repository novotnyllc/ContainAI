using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathTargetEnsurer
{
    Task<int> EnsureAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        CancellationToken cancellationToken);
}
