using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host.DockerProxy.Parsing;

internal static partial class DockerProxyValidationHelpers
{
    public static string SanitizeWorkspaceName(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "workspace";
        }

        var replaced = NonWorkspaceCharacterRegex().Replace(value, "-");
        replaced = MultiHyphenRegex().Replace(replaced, "-").Trim('-');
        return string.IsNullOrWhiteSpace(replaced) ? "workspace" : replaced;
    }

    public static bool IsValidVolumeName(string volume)
    {
        if (!VolumeNameRegex().IsMatch(volume))
        {
            return false;
        }

        if (volume.Contains(':', StringComparison.Ordinal) ||
            volume.Contains('/', StringComparison.Ordinal) ||
            volume.Contains('~', StringComparison.Ordinal))
        {
            return false;
        }

        return !string.Equals(volume, ".", StringComparison.Ordinal) && !string.Equals(volume, "..", StringComparison.Ordinal);
    }

    public static bool IsValidUnixUsername(string value) => UnixUsernameRegex().IsMatch(value);

    [GeneratedRegex("[^A-Za-z0-9._-]", RegexOptions.Compiled)]
    private static partial Regex NonWorkspaceCharacterRegex();

    [GeneratedRegex("-{2,}", RegexOptions.Compiled)]
    private static partial Regex MultiHyphenRegex();

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex VolumeNameRegex();

    [GeneratedRegex("^[a-z_][a-z0-9_-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex UnixUsernameRegex();
}
