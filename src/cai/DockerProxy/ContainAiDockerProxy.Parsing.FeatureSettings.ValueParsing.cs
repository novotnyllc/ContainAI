using System.Text.Json;

namespace ContainAI.Cli.Host;

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
