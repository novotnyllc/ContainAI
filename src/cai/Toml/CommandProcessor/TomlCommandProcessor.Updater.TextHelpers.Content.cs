namespace ContainAI.Cli.Host;

internal static partial class TomlCommandUpdaterLineHelpers
{
    public static bool SectionHasContent(List<string> lines, int start, int end)
    {
        for (var index = start; index < end && index < lines.Count; index++)
        {
            var trimmed = lines[index].Trim();
            if (trimmed.Length > 0 && !trimmed.StartsWith('#'))
            {
                return true;
            }
        }

        return false;
    }

    public static List<string> SplitLines(string content)
    {
        if (string.IsNullOrEmpty(content))
        {
            return [];
        }

        var normalized = content.Replace("\r\n", "\n", StringComparison.Ordinal);
        if (normalized.EndsWith('\n'))
        {
            normalized = normalized[..^1];
        }

        return normalized.Length == 0
            ? []
            : normalized.Split('\n').ToList();
    }

    public static string NormalizeOutputContent(List<string> lines)
    {
        if (lines.Count == 0)
        {
            return string.Empty;
        }

        var content = string.Join("\n", lines);
        return content.Length == 0 || content.EndsWith('\n')
            ? content
            : content + "\n";
    }
}
