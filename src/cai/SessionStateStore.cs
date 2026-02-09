namespace ContainAI.Cli.Host;

internal sealed class SessionStateStore
{
    private readonly string dataVolumeEnvironmentVariable;

    public SessionStateStore(string dataVolumeEnvironmentVariable = "CONTAINAI_DATA_VOLUME")
        => this.dataVolumeEnvironmentVariable = dataVolumeEnvironmentVariable;

    public async Task PersistAsync(EnsuredSession session, CancellationToken cancellationToken)
    {
        var configPath = SessionRuntimeInfrastructure.ResolveUserConfigPath();
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        if (!File.Exists(configPath))
        {
            await File.WriteAllTextAsync(configPath, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.SetWorkspaceKey(configPath, session.Workspace, "container_name", session.ContainerName),
            cancellationToken).ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(dataVolumeEnvironmentVariable)))
        {
            return;
        }

        await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.SetWorkspaceKey(configPath, session.Workspace, "data_volume", session.DataVolume),
            cancellationToken).ConfigureAwait(false);
    }
}
