namespace ContainAI.Cli.Host;

internal static class TomlCommandUpdaterLineHelpers
{
    public static bool IsAnyTableHeader(string trimmed) => trimmed.StartsWith('[');

    public static bool IsTargetHeader(string trimmed, string header)
    {
        if (string.Equals(trimmed, header, StringComparison.Ordinal))
        {
            return true;
        }

        if (trimmed.StartsWith(header, StringComparison.Ordinal) && trimmed.Length > header.Length)
        {
            var remainder = trimmed[header.Length..].TrimStart();
            return remainder.StartsWith('#');
        }

        return false;
    }

    public static bool IsTomlKeyAssignmentLine(string trimmedLine, string key)
    {
        if (string.IsNullOrWhiteSpace(trimmedLine) || string.IsNullOrWhiteSpace(key))
        {
            return false;
        }

        var line = trimmedLine.AsSpan();
        var keySpan = key.AsSpan();
        if (!line.StartsWith(keySpan, StringComparison.Ordinal))
        {
            return false;
        }

        var position = keySpan.Length;
        while (position < line.Length && char.IsWhiteSpace(line[position]))
        {
            position++;
        }

        return position < line.Length && line[position] == '=';
    }

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
