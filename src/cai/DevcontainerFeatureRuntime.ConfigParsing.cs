using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private sealed class DevcontainerFeatureConfigService
    {
        private readonly Func<string, string?> environmentVariableReader;
        private readonly JsonContext jsonContext;
        private readonly Regex volumeNamePattern;
        private readonly Regex unixUsernamePattern;

        public DevcontainerFeatureConfigService()
        {
            environmentVariableReader = Environment.GetEnvironmentVariable;
            jsonContext = JsonContext.Default;
            volumeNamePattern = VolumeNameRegex();
            unixUsernamePattern = UnixUsernameRegex();
        }

        public bool ValidateFeatureConfig(FeatureConfig config, out string error)
        {
            if (!volumeNamePattern.IsMatch(config.DataVolume))
            {
                error = $"ERROR: Invalid dataVolume \"{config.DataVolume}\". Must be alphanumeric with ._- allowed.";
                return false;
            }

            if (!string.Equals(config.RemoteUser, "auto", StringComparison.Ordinal) && !unixUsernamePattern.IsMatch(config.RemoteUser))
            {
                error = $"ERROR: Invalid remoteUser \"{config.RemoteUser}\". Must be \"auto\" or a valid Unix username.";
                return false;
            }

            error = string.Empty;
            return true;
        }

        public bool TryParseFeatureBoolean(string name, bool defaultValue, out bool value, out string error)
        {
            var rawValue = environmentVariableReader(name);
            if (string.IsNullOrWhiteSpace(rawValue))
            {
                value = defaultValue;
                error = string.Empty;
                return true;
            }

            switch (rawValue.Trim())
            {
                case "true":
                case "TRUE":
                case "True":
                case "1":
                    value = true;
                    error = string.Empty;
                    return true;
                case "false":
                case "FALSE":
                case "False":
                case "0":
                    value = false;
                    error = string.Empty;
                    return true;
                default:
                    value = defaultValue;
                    error = $"ERROR: Invalid {name} \"{rawValue}\". Must be true or false.";
                    return false;
            }
        }

        public async Task<FeatureConfig?> LoadFeatureConfigAsync(string path, CancellationToken cancellationToken)
        {
            try
            {
                var json = await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
                return JsonSerializer.Deserialize(json, jsonContext.FeatureConfig);
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

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex VolumeNameRegex();

    [GeneratedRegex("^[a-z_][a-z0-9_-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex UnixUsernameRegex();

    [JsonSerializable(typeof(FeatureConfig))]
    [JsonSerializable(typeof(LinkSpecDocument))]
    private partial class JsonContext : JsonSerializerContext;

    internal sealed record FeatureConfig(
        [property: JsonPropertyName("data_volume")] string DataVolume,
        [property: JsonPropertyName("enable_credentials")] bool EnableCredentials,
        [property: JsonPropertyName("enable_ssh")] bool EnableSsh,
        [property: JsonPropertyName("install_docker")] bool InstallDocker,
        [property: JsonPropertyName("remote_user")] string RemoteUser);

    internal sealed record LinkSpecDocument(
        [property: JsonPropertyName("home_dir")] string? HomeDirectory,
        [property: JsonPropertyName("links")] IReadOnlyList<LinkEntry>? Links);

    internal sealed record LinkEntry(
        [property: JsonPropertyName("link")] string Link,
        [property: JsonPropertyName("target")] string Target,
        [property: JsonPropertyName("remove_first")] bool? RemoveFirst);
}
