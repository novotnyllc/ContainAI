using ContainAI.Cli.Host;
using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace.DataVolume;

internal interface ISessionTargetConfiguredDataVolumeResolver
{
    Task<string?> ResolveConfiguredDataVolumeAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken);
}
