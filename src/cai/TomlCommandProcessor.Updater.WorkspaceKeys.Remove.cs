namespace ContainAI.Cli.Host;

internal static partial class TomlWorkspaceKeyUpdater
{
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
}
