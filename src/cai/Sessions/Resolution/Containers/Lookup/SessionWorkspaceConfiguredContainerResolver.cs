using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Containers;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers.Lookup;

internal sealed class SessionWorkspaceConfiguredContainerResolver(
    ISessionDockerQueryRunner dockerQueryRunner,
    ISessionWorkspaceConfigReader workspaceConfigReader,
    ISessionContainerLabelReader containerLabelReader) : ISessionWorkspaceConfiguredContainerResolver
{
    public async Task<ContainerLookupResult?> TryResolveAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var configuredName = await workspaceConfigReader
            .TryResolveWorkspaceContainerNameAsync(workspace, cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(configuredName))
        {
            return null;
        }

        var inspect = await dockerQueryRunner.QueryContainerInspectAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return null;
        }

        var labels = await containerLabelReader.ReadContainerLabelsAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
        return string.Equals(labels.Workspace, workspace, StringComparison.Ordinal)
            ? ContainerLookupResult.Success(configuredName)
            : null;
    }
}
