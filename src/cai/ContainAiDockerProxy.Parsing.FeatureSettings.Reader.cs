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

internal static class DockerProxyFeatureSettingsValueParsing
{
    public static string GetDataVolume(JsonElement featureElement, string defaultDataVolume)
    {
        var dataVolume = defaultDataVolume;
        if (featureElement.ValueKind == JsonValueKind.Object &&
            featureElement.TryGetProperty("dataVolume", out var dataVolumeElement) &&
            dataVolumeElement.ValueKind == JsonValueKind.String)
        {
            var candidate = dataVolumeElement.GetString();
            if (!string.IsNullOrWhiteSpace(candidate) && DockerProxyValidationHelpers.IsValidVolumeName(candidate!))
            {
                dataVolume = candidate!;
            }
        }

        return dataVolume;
    }

    public static bool GetEnableCredentials(JsonElement featureElement)
    {
        if (featureElement.ValueKind != JsonValueKind.Object ||
            !featureElement.TryGetProperty("enableCredentials", out var credentialsElement))
        {
            return false;
        }

        return credentialsElement.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String when bool.TryParse(credentialsElement.GetString(), out var parsed) => parsed,
            _ => false,
        };
    }

    public static string GetRemoteUser(JsonElement rootElement, JsonElement featureElement)
    {
        var remoteUser = "vscode";
        if (TryGetValidatedRemoteUser(featureElement, "remoteUser", out var featureRemoteUser))
        {
            remoteUser = featureRemoteUser;
        }

        if (TryGetValidatedRemoteUser(rootElement, "remoteUser", out var topLevelRemoteUser))
        {
            remoteUser = topLevelRemoteUser;
        }

        return remoteUser;
    }

    private static bool TryGetValidatedRemoteUser(JsonElement element, string propertyName, out string remoteUser)
    {
        remoteUser = string.Empty;
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var remoteUserElement) ||
            remoteUserElement.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        var candidate = remoteUserElement.GetString();
        if (string.IsNullOrWhiteSpace(candidate) ||
            string.Equals(candidate, "auto", StringComparison.Ordinal) ||
            !DockerProxyValidationHelpers.IsValidUnixUsername(candidate!))
        {
            return false;
        }

        remoteUser = candidate!;
        return true;
    }
}
