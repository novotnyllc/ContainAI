using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal static partial class DevcontainerFeatureValidationRegexes
{
    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    internal static partial Regex VolumeNameRegex();

    [GeneratedRegex("^[a-z_][a-z0-9_-]*$", RegexOptions.CultureInvariant)]
    internal static partial Regex UnixUsernameRegex();
}
