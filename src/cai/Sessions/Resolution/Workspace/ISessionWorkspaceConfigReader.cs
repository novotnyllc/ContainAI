using ContainAI.Cli.Host;
using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace;

internal interface ISessionWorkspaceConfigReader
{
    Task<string?> TryResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken);
}
