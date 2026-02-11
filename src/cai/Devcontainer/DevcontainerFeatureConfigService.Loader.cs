using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureConfigService
{
    public async Task<FeatureConfig?> LoadFeatureConfigAsync(string path, CancellationToken cancellationToken)
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
