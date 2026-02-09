namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandUpdater
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
}
