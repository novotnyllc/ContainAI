using ContainAI.Cli.Host.Sessions.Infrastructure;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace;

internal interface ISessionTargetContainerNameGenerationService
{
    Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken);
}
