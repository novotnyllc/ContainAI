namespace ContainAI.Cli.Host;

internal static class TomlWorkspaceSectionFormatter
{
    public static string BuildWorkspaceHeader(string workspacePath)
        => $"[workspace.\"{TomlCommandTextFormatter.EscapeTomlKey(workspacePath)}\"]";

    public static string BuildKeyLine(string key, string value)
        => $"{key} = {TomlCommandTextFormatter.FormatTomlString(value)}";
}
