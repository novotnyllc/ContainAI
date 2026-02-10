using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal static partial class TomlCommandRegexProvider
{
    public static readonly Regex WorkspaceKeyRegex = WorkspaceKeyRegexFactory();
    public static readonly Regex GlobalKeyRegex = GlobalKeyRegexFactory();

    [GeneratedRegex("^[a-zA-Z_][a-zA-Z0-9_]*$", RegexOptions.CultureInvariant)]
    private static partial Regex WorkspaceKeyRegexFactory();

    [GeneratedRegex("^[a-zA-Z_][a-zA-Z0-9_.]*$", RegexOptions.CultureInvariant)]
    private static partial Regex GlobalKeyRegexFactory();
}
