using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IInstallCommandContextResolver
{
    Task<InstallCommandContextResolutionResult> ResolveAsync(InstallCommandOptions options, CancellationToken cancellationToken);
}
