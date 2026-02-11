namespace ContainAI.Cli.Host;

internal static class TomlGlobalKeyRemover
{
    public static string RemoveGlobalKey(string content, string[] keyParts)
    {
        var lines = TomlCommandUpdaterLineHelpers.SplitLines(content);
        var newLines = new List<string>(lines.Count);

        if (keyParts.Length == 1)
        {
            return RemoveRootKey(lines, newLines, keyParts[0]);
        }

        return RemoveNestedKey(lines, newLines, keyParts);
    }

    private static string RemoveRootKey(
        IReadOnlyList<string> lines,
        List<string> newLines,
        string keyPart)
    {
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (!TomlCommandUpdaterLineHelpers.IsAnyTableHeader(trimmed) &&
                TomlCommandUpdaterLineHelpers.IsTomlKeyAssignmentLine(trimmed, keyPart))
            {
                continue;
            }

            newLines.Add(line);
        }

        return TomlCommandUpdaterLineHelpers.NormalizeOutputContent(newLines);
    }

    private static string RemoveNestedKey(
        IReadOnlyList<string> lines,
        List<string> newLines,
        string[] keyParts)
    {
        var sectionHeader = $"[{keyParts[0]}]";
        var inTargetSection = false;
        var sectionStart = -1;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            if (TomlCommandUpdaterLineHelpers.IsTargetHeader(trimmed, sectionHeader))
            {
                inTargetSection = true;
                sectionStart = newLines.Count;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && TomlCommandUpdaterLineHelpers.IsAnyTableHeader(trimmed))
            {
                inTargetSection = false;
            }

            if (inTargetSection && TomlCommandUpdaterLineHelpers.IsTomlKeyAssignmentLine(trimmed, keyParts[^1]))
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
                if (TomlCommandUpdaterLineHelpers.IsAnyTableHeader(newLines[index].Trim()))
                {
                    sectionEnd = index;
                    break;
                }
            }

            if (!TomlCommandUpdaterLineHelpers.SectionHasContent(newLines, sectionStart + 1, sectionEnd))
            {
                newLines.RemoveRange(sectionStart, sectionEnd - sectionStart);
            }
        }

        return TomlCommandUpdaterLineHelpers.NormalizeOutputContent(newLines);
    }
}
