using System.Collections.Frozen;

namespace ContainAI.Cli;

internal static class CommandCatalog
{
    public static readonly IReadOnlyList<string> RoutedCommandOrder =
    [
        "run",
        "shell",
        "exec",
        "doctor",
        "setup",
        "validate",
        "docker",
        "import",
        "export",
        "sync",
        "stop",
        "status",
        "gc",
        "ssh",
        "links",
        "config",
        "manifest",
        "template",
        "update",
        "refresh",
        "uninstall",
        "completion",
        "version",
        "help",
        "system",
        "acp",
    ];

    public static readonly FrozenSet<string> RoutedCommands =
        RoutedCommandOrder.ToFrozenSet(StringComparer.Ordinal);

    public static readonly FrozenSet<string> RootParserTokens =
        new[]
        {
            "help",
            "--help",
            "-h",
        }.ToFrozenSet(StringComparer.Ordinal);
}
