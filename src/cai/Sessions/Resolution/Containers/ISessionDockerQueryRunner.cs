using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal interface ISessionDockerQueryRunner
{
    Task<ProcessResult> QueryContainerLabelFieldsAsync(string containerName, string context, CancellationToken cancellationToken);

    Task<ProcessResult> QueryContainerInspectAsync(string containerName, string context, CancellationToken cancellationToken);

    Task<ProcessResult> QueryContainersByWorkspaceLabelAsync(string workspace, string context, CancellationToken cancellationToken);

    Task<ProcessResult> QueryContainerNameByIdAsync(string context, string containerId, CancellationToken cancellationToken);

    Task<List<string>> FindContextsContainingContainerAsync(
        string containerName,
        IReadOnlyList<string> contexts,
        CancellationToken cancellationToken);
}
