using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestTargetEnsureExecutor
{
    Task<int> EnsureAsync(string volume, string command, CancellationToken cancellationToken);
}
