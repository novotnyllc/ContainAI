using ContainAI.Cli.Host.ConfigManifest.Reading;

namespace ContainAI.Cli.Host.ConfigManifest;

internal interface IConfigReadOperation
{
    Task<int> ListAsync(string configPath, CancellationToken cancellationToken);

    Task<int> GetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);
}
