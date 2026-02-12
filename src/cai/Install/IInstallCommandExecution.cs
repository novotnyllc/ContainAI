using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IInstallCommandExecution
{
    Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken);
}
