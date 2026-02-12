using ContainAI.Cli.Host;
using ContainAI.Cli.Host.Sessions.Infrastructure;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace;

internal interface ISessionTargetConfiguredContextResolver
{
    Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken);
}
