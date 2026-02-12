using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IInstallSetupRunner
{
    Task<int> RunSetupAsync(string installedBinary, InstallCommandOptions options, CancellationToken cancellationToken);
}
