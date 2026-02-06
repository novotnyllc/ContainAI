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
        "acp",
    ];

    public static readonly IReadOnlySet<string> RoutedCommands = new HashSet<string>(RoutedCommandOrder, StringComparer.Ordinal);

    public static readonly IReadOnlySet<string> RootParserTokens = new HashSet<string>(StringComparer.Ordinal)
    {
        "help",
        "--help",
        "-h",
    };
}
