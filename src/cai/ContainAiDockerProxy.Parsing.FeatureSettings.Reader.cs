using System.Text.Json;

namespace ContainAI.Cli.Host;

internal static class DockerProxyFeatureSettingsReader
{
    public static bool TryReadFeatureSettings(
        string configFile,
        TextWriter stderr,
        ContainAiDockerProxyOptions options,
        out FeatureSettings settings)
    {
        settings = FeatureSettings.Default(options.DefaultDataVolume);

        if (!File.Exists(configFile))
        {
            return false;
        }

        try
        {
            var raw = File.ReadAllText(configFile);
            var stripped = DockerProxyJsoncCommentStripper.Strip(raw);
            using var document = JsonDocument.Parse(stripped);
            if (!document.RootElement.TryGetProperty("features", out var features) || features.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            foreach (var feature in features.EnumerateObject())
            {
                if (!feature.Name.Contains("containai", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var featureElement = feature.Value;
                var dataVolume = DockerProxyFeatureSettingsValueParsing.GetDataVolume(featureElement, options.DefaultDataVolume);
                var enableCredentials = DockerProxyFeatureSettingsValueParsing.GetEnableCredentials(featureElement);
                var remoteUser = DockerProxyFeatureSettingsValueParsing.GetRemoteUser(document.RootElement, featureElement);

                settings = new FeatureSettings(true, dataVolume, enableCredentials, remoteUser);
                return true;
            }

            return false;
        }
        catch (Exception ex) when (IsHandledParseException(ex))
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
    }

    private static bool IsHandledParseException(Exception ex)
        => ex is IOException or UnauthorizedAccessException or JsonException or ArgumentException or NotSupportedException;
}
