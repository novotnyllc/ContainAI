using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host.Manifests.Apply;

internal static partial class ManifestAgentShimRegex
{
    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    public static partial Regex CommandName();
}
