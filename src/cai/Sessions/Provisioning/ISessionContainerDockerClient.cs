using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionContainerDockerClient
{
    Task<ProcessResult> CreateContainerAsync(string context, IReadOnlyList<string> dockerArgs, CancellationToken cancellationToken);

    Task<ProcessResult> StartContainerAsync(string context, string containerName, CancellationToken cancellationToken);

    Task<ProcessResult> StopContainerAsync(string context, string containerName, CancellationToken cancellationToken);

    Task<ProcessResult> RemoveContainerAsync(string context, string containerName, CancellationToken cancellationToken);

    Task<ProcessResult> InspectContainerStateAsync(string context, string containerName, CancellationToken cancellationToken);
}
