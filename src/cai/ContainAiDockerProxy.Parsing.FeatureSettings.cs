using System.Text;
using System.Text.Json;

namespace ContainAI.Cli.Host;

internal static class DockerProxyFeatureSettingsParsing
{
    public static string StripJsoncComments(string content)
    {
        var builder = new StringBuilder(content.Length);
        var inString = false;
        var escape = false;

        for (var index = 0; index < content.Length; index++)
        {
            var current = content[index];

            if (escape)
            {
                builder.Append(current);
                escape = false;
                continue;
            }

            if (current == '\\' && inString)
            {
                builder.Append(current);
                escape = true;
                continue;
            }

            if (current == '"')
            {
                inString = !inString;
                builder.Append(current);
                continue;
            }

            if (!inString && current == '/' && index + 1 < content.Length)
            {
                var next = content[index + 1];
                if (next == '/')
                {
                    while (index < content.Length && content[index] != '\n')
                    {
                        index++;
                    }

                    if (index < content.Length)
                    {
                        builder.Append('\n');
                    }

                    continue;
                }

                if (next == '*')
                {
                    index += 2;
                    while (index + 1 < content.Length && !(content[index] == '*' && content[index + 1] == '/'))
                    {
                        if (content[index] == '\n')
                        {
                            builder.Append('\n');
                        }

                        index++;
                    }

                    index++;
                    continue;
                }
            }

            builder.Append(current);
        }

        return builder.ToString();
    }

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
            var stripped = StripJsoncComments(raw);
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
                var dataVolume = GetDataVolume(featureElement, options.DefaultDataVolume);
                var enableCredentials = GetEnableCredentials(featureElement);
                var remoteUser = GetRemoteUser(document.RootElement, featureElement);

                settings = new FeatureSettings(true, dataVolume, enableCredentials, remoteUser);
                return true;
            }

            return false;
        }
        catch (IOException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (UnauthorizedAccessException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (JsonException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (ArgumentException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (NotSupportedException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
    }

    private static string GetDataVolume(JsonElement featureElement, string defaultDataVolume)
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

    private static bool GetEnableCredentials(JsonElement featureElement)
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

    private static string GetRemoteUser(JsonElement rootElement, JsonElement featureElement)
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
