namespace ContainAI.Cli.Host;

internal static class TomlWorkspaceKeyUpdater
{
    public static string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
    {
        var header = BuildWorkspaceHeader(workspacePath);
        var keyLine = BuildKeyLine(key, value);

        var lines = TomlCommandUpdaterLineHelpers.SplitLines(content);
        var newLines = new List<string>(lines.Count + 4);
        var inTargetSection = false;
        var foundSection = false;
        var keyUpdated = false;
        var lastContentIndex = -1;

        for (var index = 0; index < lines.Count; index++)
        {
            var line = lines[index];
            var trimmed = line.Trim();

            if (TomlCommandUpdaterLineHelpers.IsTargetHeader(trimmed, header))
            {
                inTargetSection = true;
                foundSection = true;
                newLines.Add(line);
                lastContentIndex = newLines.Count - 1;
                continue;
            }

            if (inTargetSection && TomlCommandUpdaterLineHelpers.IsAnyTableHeader(trimmed))
            {
                if (!keyUpdated)
                {
                    InsertKeyLine(newLines, keyLine, lastContentIndex);
                    keyUpdated = true;
                }

                inTargetSection = false;
            }

            if (inTargetSection && TomlCommandUpdaterLineHelpers.IsTomlKeyAssignmentLine(trimmed, key))
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
            InsertKeyLine(newLines, keyLine, lastContentIndex);
        }

        if (!foundSection)
        {
            AppendSection(newLines, header, keyLine);
        }

        return TomlCommandUpdaterLineHelpers.NormalizeOutputContent(newLines);
    }

    public static string RemoveWorkspaceKey(string content, string workspacePath, string key)
    {
        var header = BuildWorkspaceHeader(workspacePath);
        var lines = TomlCommandUpdaterLineHelpers.SplitLines(content);
        var newLines = new List<string>(lines.Count);

        var inTargetSection = false;
        var sectionStart = -1;
        var sectionEnd = -1;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (TomlCommandUpdaterLineHelpers.IsTargetHeader(trimmed, header))
            {
                inTargetSection = true;
                sectionStart = newLines.Count;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && TomlCommandUpdaterLineHelpers.IsAnyTableHeader(trimmed))
            {
                sectionEnd = newLines.Count;
                inTargetSection = false;
            }

            if (inTargetSection && TomlCommandUpdaterLineHelpers.IsTomlKeyAssignmentLine(trimmed, key))
            {
                continue;
            }

            newLines.Add(line);
        }

        if (inTargetSection)
        {
            sectionEnd = newLines.Count;
        }

        if (sectionStart >= 0 && sectionEnd > sectionStart && !TomlCommandUpdaterLineHelpers.SectionHasContent(newLines, sectionStart + 1, sectionEnd))
        {
            newLines.RemoveRange(sectionStart, sectionEnd - sectionStart);
            TrimTrailingBlankLines(newLines);
        }

        return TomlCommandUpdaterLineHelpers.NormalizeOutputContent(newLines);
    }

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
