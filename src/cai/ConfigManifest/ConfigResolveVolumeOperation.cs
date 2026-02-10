namespace ContainAI.Cli.Host.ConfigManifest;

internal interface IConfigResolveVolumeOperation
{
    Task<int> ResolveVolumeAsync(ConfigCommandRequest request, CancellationToken cancellationToken);
}

internal sealed class ConfigResolveVolumeOperation(
    TextWriter standardOutput,
    ICaiConfigRuntime runtime) : IConfigResolveVolumeOperation
{
    public async Task<int> ResolveVolumeAsync(ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        var workspace = string.IsNullOrWhiteSpace(request.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(runtime.ExpandHomePath(request.Workspace));

        var volume = await runtime.ResolveDataVolumeAsync(workspace, request.Key, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            return 1;
        }

        await standardOutput.WriteLineAsync(volume).ConfigureAwait(false);
        return 0;
    }
}
