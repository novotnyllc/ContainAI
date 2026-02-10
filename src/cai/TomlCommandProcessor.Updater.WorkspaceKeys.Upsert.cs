namespace ContainAI.Cli.Host;

internal static partial class TomlWorkspaceKeyUpdater
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
}
