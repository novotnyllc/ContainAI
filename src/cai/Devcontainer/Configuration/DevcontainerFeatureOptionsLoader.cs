using System.Text.Json;

namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal interface IDevcontainerFeatureOptionsLoader
{
    Task<FeatureConfig?> LoadAsync(string path, CancellationToken cancellationToken);
}

internal sealed class DevcontainerFeatureOptionsLoader : IDevcontainerFeatureOptionsLoader
{
    public async Task<FeatureConfig?> LoadAsync(string path, CancellationToken cancellationToken)
    {
        try
        {
            var json = await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
            return JsonSerializer.Deserialize(json, DevcontainerFeatureJsonContext.Default.FeatureConfig);
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
    }
}
