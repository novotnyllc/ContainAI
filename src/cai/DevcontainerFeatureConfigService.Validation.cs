namespace ContainAI.Cli.Host;

using System.Text.RegularExpressions;

internal sealed partial class DevcontainerFeatureConfigService
{
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

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex VolumeNameRegex();

    [GeneratedRegex("^[a-z_][a-z0-9_-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex UnixUsernameRegex();
}
