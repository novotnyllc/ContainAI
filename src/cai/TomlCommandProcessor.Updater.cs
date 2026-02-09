namespace ContainAI.Cli.Host;

internal sealed class TomlCommandUpdater : ITomlCommandUpdater
{
    public string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
    {
        var header = $"[workspace.\"{TomlCommandTextFormatter.EscapeTomlKey(workspacePath)}\"]";
        var keyLine = $"{key} = {TomlCommandTextFormatter.FormatTomlString(value)}";

        var lines = SplitLines(content);
        var newLines = new List<string>(lines.Count + 4);
        var inTargetSection = false;
        var foundSection = false;
        var keyUpdated = false;
        var lastContentIndex = -1;

        for (var index = 0; index < lines.Count; index++)
        {
            var line = lines[index];
            var trimmed = line.Trim();

            if (IsTargetHeader(trimmed, header))
            {
                inTargetSection = true;
                foundSection = true;
                newLines.Add(line);
                lastContentIndex = newLines.Count - 1;
                continue;
            }

            if (inTargetSection && IsAnyTableHeader(trimmed))
            {
                if (!keyUpdated)
                {
                    var insertPos = Math.Clamp(lastContentIndex + 1, 0, newLines.Count);
                    newLines.Insert(insertPos, keyLine);
                    keyUpdated = true;
                }

                inTargetSection = false;
            }

            if (inTargetSection && IsTomlKeyAssignmentLine(trimmed, key))
            {
                newLines.Add(keyLine);
                lastContentIndex = newLines.Count - 1;
                keyUpdated = true;
                continue;
            }

            newLines.Add(line);
            if (inTargetSection && trimmed.Length > 0)
            {
                lastContentIndex = newLines.Count - 1;
            }
        }

        if (inTargetSection && !keyUpdated)
        {
            var insertPos = Math.Clamp(lastContentIndex + 1, 0, newLines.Count);
            newLines.Insert(insertPos, keyLine);
            keyUpdated = true;
        }

        if (!foundSection)
        {
            if (newLines.Count > 0 && newLines.Any(static line => !string.IsNullOrWhiteSpace(line)))
            {
                newLines.Add(string.Empty);
            }

            newLines.Add(header);
            newLines.Add(keyLine);
        }

        return NormalizeOutputContent(newLines);
    }

    public string RemoveWorkspaceKey(string content, string workspacePath, string key)
    {
        var header = $"[workspace.\"{TomlCommandTextFormatter.EscapeTomlKey(workspacePath)}\"]";
        var lines = SplitLines(content);
        var newLines = new List<string>(lines.Count);

        var inTargetSection = false;
        var sectionStart = -1;
        var sectionEnd = -1;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (IsTargetHeader(trimmed, header))
            {
                inTargetSection = true;
                sectionStart = newLines.Count;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && IsAnyTableHeader(trimmed))
            {
                sectionEnd = newLines.Count;
                inTargetSection = false;
            }

            if (inTargetSection && IsTomlKeyAssignmentLine(trimmed, key))
            {
                continue;
            }

            newLines.Add(line);
        }

        if (inTargetSection)
        {
            sectionEnd = newLines.Count;
        }

        if (sectionStart >= 0 && sectionEnd > sectionStart && !SectionHasContent(newLines, sectionStart + 1, sectionEnd))
        {
            newLines.RemoveRange(sectionStart, sectionEnd - sectionStart);
            while (newLines.Count > 0 && string.IsNullOrWhiteSpace(newLines[^1]))
            {
                newLines.RemoveAt(newLines.Count - 1);
            }
        }

        return NormalizeOutputContent(newLines);
    }

    public string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
    {
        var lines = SplitLines(content);
        var newLines = new List<string>(lines.Count + 3);
        var keyLine = $"{keyParts[^1]} = {formattedValue}";

        if (keyParts.Length == 1)
        {
            var keyUpdated = false;
            var inTable = false;

            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (IsAnyTableHeader(trimmed))
                {
                    inTable = true;
                    if (!keyUpdated)
                    {
                        newLines.Add(keyLine);
                        keyUpdated = true;
                    }

                    newLines.Add(line);
                    continue;
                }

                if (!inTable && IsTomlKeyAssignmentLine(trimmed, keyParts[0]))
                {
                    newLines.Add(keyLine);
                    keyUpdated = true;
                    continue;
                }

                newLines.Add(line);
            }

            if (!keyUpdated)
            {
                if (inTable)
                {
                    var insertAt = newLines.FindIndex(static line => IsAnyTableHeader(line.Trim()));
                    if (insertAt >= 0)
                    {
                        newLines.Insert(insertAt, keyLine);
                    }
                    else
                    {
                        newLines.Add(keyLine);
                    }
                }
                else
                {
                    newLines.Add(keyLine);
                }
            }

            return NormalizeOutputContent(newLines);
        }

        var sectionHeader = $"[{keyParts[0]}]";
        var inTargetSection = false;
        var foundSection = false;
        var keyUpdatedNested = false;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            if (IsTargetHeader(trimmed, sectionHeader))
            {
                inTargetSection = true;
                foundSection = true;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && IsAnyTableHeader(trimmed))
            {
                if (!keyUpdatedNested)
                {
                    newLines.Add(keyLine);
                    keyUpdatedNested = true;
                }

                inTargetSection = false;
            }

            if (inTargetSection && IsTomlKeyAssignmentLine(trimmed, keyParts[^1]))
            {
                newLines.Add(keyLine);
                keyUpdatedNested = true;
                continue;
            }

            newLines.Add(line);
        }

        if (inTargetSection && !keyUpdatedNested)
        {
            newLines.Add(keyLine);
            keyUpdatedNested = true;
        }

        if (!foundSection)
        {
            if (newLines.Count > 0 && newLines.Any(static line => !string.IsNullOrWhiteSpace(line)))
            {
                newLines.Add(string.Empty);
            }

            newLines.Add(sectionHeader);
            newLines.Add(keyLine);
        }

        return NormalizeOutputContent(newLines);
    }

    public string RemoveGlobalKey(string content, string[] keyParts)
    {
        var lines = SplitLines(content);
        var newLines = new List<string>(lines.Count);

        if (keyParts.Length == 1)
        {
            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (!IsAnyTableHeader(trimmed) && IsTomlKeyAssignmentLine(trimmed, keyParts[0]))
                {
                    continue;
                }

                newLines.Add(line);
            }

            return NormalizeOutputContent(newLines);
        }

        var sectionHeader = $"[{keyParts[0]}]";
        var inTargetSection = false;
        var sectionStart = -1;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            if (IsTargetHeader(trimmed, sectionHeader))
            {
                inTargetSection = true;
                sectionStart = newLines.Count;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && IsAnyTableHeader(trimmed))
            {
                inTargetSection = false;
            }

            if (inTargetSection && IsTomlKeyAssignmentLine(trimmed, keyParts[^1]))
            {
                continue;
            }

            newLines.Add(line);
        }

        if (sectionStart >= 0)
        {
            var sectionEnd = newLines.Count;
            for (var index = sectionStart + 1; index < newLines.Count; index++)
            {
                if (IsAnyTableHeader(newLines[index].Trim()))
                {
                    sectionEnd = index;
                    break;
                }
            }

            if (!SectionHasContent(newLines, sectionStart + 1, sectionEnd))
            {
                newLines.RemoveRange(sectionStart, sectionEnd - sectionStart);
            }
        }

        return NormalizeOutputContent(newLines);
    }

    private static bool IsAnyTableHeader(string trimmed) => trimmed.StartsWith('[');

    private static bool IsTargetHeader(string trimmed, string header)
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

    private static bool IsTomlKeyAssignmentLine(string trimmedLine, string key)
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

    private static bool SectionHasContent(List<string> lines, int start, int end)
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

    private static List<string> SplitLines(string content)
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

    private static string NormalizeOutputContent(List<string> lines)
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

internal static class TomlCommandTextFormatter
{
    public static string FormatTomlString(string value)
    {
        if (value.IndexOfAny(['\n', '\r', '\t', '"', '\\']) >= 0)
        {
            var escaped = value
                .Replace("\\", "\\\\", StringComparison.Ordinal)
                .Replace("\"", "\\\"", StringComparison.Ordinal)
                .Replace("\n", "\\n", StringComparison.Ordinal)
                .Replace("\r", "\\r", StringComparison.Ordinal)
                .Replace("\t", "\\t", StringComparison.Ordinal);
            return $"\"{escaped}\"";
        }

        return $"\"{value}\"";
    }

    public static string EscapeTomlKey(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("\"", "\\\"", StringComparison.Ordinal);
}
