namespace ContainAI.Cli.Host.ConfigManifest;

internal interface IConfigResolveVolumeOperation
{
    Task<int> ResolveVolumeAsync(ConfigCommandRequest request, CancellationToken cancellationToken);
}
