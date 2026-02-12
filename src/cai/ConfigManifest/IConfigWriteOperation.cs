namespace ContainAI.Cli.Host.ConfigManifest;

internal interface IConfigWriteOperation
{
    Task<int> SetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);

    Task<int> UnsetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);
}
