using ContainAI.Cli.Host;
using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.State;

internal sealed class SessionStateStore
{
    private readonly string dataVolumeEnvironmentVariable;
    private readonly ISessionRuntimeOperations runtimeOperations;

    public SessionStateStore(string dataVolumeEnvironmentVariable = "CONTAINAI_DATA_VOLUME")
        : this(dataVolumeEnvironmentVariable, new SessionRuntimeOperations())
    {
    }

    internal SessionStateStore(string dataVolumeEnvironmentVariable, ISessionRuntimeOperations sessionRuntimeOperations)
    {
        this.dataVolumeEnvironmentVariable = dataVolumeEnvironmentVariable;
        runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));
    }

    public async Task PersistAsync(EnsuredSession session, CancellationToken cancellationToken)
    {
        var configPath = runtimeOperations.ResolveUserConfigPath();
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        if (!File.Exists(configPath))
        {
            await File.WriteAllTextAsync(configPath, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        await runtimeOperations.RunTomlAsync(
            () => TomlCommandProcessor.SetWorkspaceKey(configPath, session.Workspace, "container_name", session.ContainerName),
            cancellationToken).ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(dataVolumeEnvironmentVariable)))
        {
            return;
        }

        await runtimeOperations.RunTomlAsync(
            () => TomlCommandProcessor.SetWorkspaceKey(configPath, session.Workspace, "data_volume", session.DataVolume),
            cancellationToken).ConfigureAwait(false);
    }
}
