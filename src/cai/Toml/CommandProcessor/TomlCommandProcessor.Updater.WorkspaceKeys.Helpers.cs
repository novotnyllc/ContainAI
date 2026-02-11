namespace ContainAI.Cli.Host;

internal static partial class TomlWorkspaceKeyUpdater
{
    private static string BuildWorkspaceHeader(string workspacePath)
        => $"[workspace.\"{TomlCommandTextFormatter.EscapeTomlKey(workspacePath)}\"]";

    private static string BuildKeyLine(string key, string value)
        => $"{key} = {TomlCommandTextFormatter.FormatTomlString(value)}";

    private static void InsertKeyLine(List<string> lines, string keyLine, int lastContentIndex)
    {
        var insertPos = Math.Clamp(lastContentIndex + 1, 0, lines.Count);
        lines.Insert(insertPos, keyLine);
    }

    private static void AppendSection(List<string> lines, string header, string keyLine)
    {
        if (lines.Count > 0 && lines.Any(static line => !string.IsNullOrWhiteSpace(line)))
        {
            lines.Add(string.Empty);
        }

        lines.Add(header);
        lines.Add(keyLine);
    }

    private static void TrimTrailingBlankLines(List<string> lines)
    {
        while (lines.Count > 0 && string.IsNullOrWhiteSpace(lines[^1]))
        {
            lines.RemoveAt(lines.Count - 1);
        }
    }
}
