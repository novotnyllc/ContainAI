namespace ContainAI.Cli.Host.ConfigManifest;

internal interface IConfigWriteOperation
{
    Task<int> SetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);

    Task<int> UnsetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);
}

internal sealed partial class ConfigWriteOperation(
    TextWriter standardError,
    ICaiConfigRuntime runtime) : IConfigWriteOperation;
