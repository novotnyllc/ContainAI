using System.Text.Json;
using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal interface IDevcontainerFeatureConfigService
{
    bool ValidateFeatureConfig(FeatureConfig config, out string error);

    bool TryParseFeatureBoolean(string name, bool defaultValue, out bool value, out string error);

    Task<FeatureConfig?> LoadFeatureConfigAsync(string path, CancellationToken cancellationToken);
}

internal sealed partial class DevcontainerFeatureConfigService : IDevcontainerFeatureConfigService
{
    private readonly Func<string, string?> environmentVariableReader;

    public DevcontainerFeatureConfigService()
        : this(Environment.GetEnvironmentVariable)
    {
    }

    internal DevcontainerFeatureConfigService(Func<string, string?> environmentVariableReader)
        => this.environmentVariableReader = environmentVariableReader ?? throw new ArgumentNullException(nameof(environmentVariableReader));

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

    public bool ValidateFeatureConfig(FeatureConfig config, out string error)
    {
        if (!VolumeNameRegex().IsMatch(config.DataVolume))
        {
            error = $"ERROR: Invalid dataVolume \"{config.DataVolume}\". Must be alphanumeric with ._- allowed.";
            return false;
        }

        if (!string.Equals(config.RemoteUser, "auto", StringComparison.Ordinal) && !UnixUsernameRegex().IsMatch(config.RemoteUser))
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

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex VolumeNameRegex();

    [GeneratedRegex("^[a-z_][a-z0-9_-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex UnixUsernameRegex();
}
