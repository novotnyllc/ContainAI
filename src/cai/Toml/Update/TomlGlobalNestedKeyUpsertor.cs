namespace ContainAI.Cli.Host;

internal static class TomlGlobalNestedKeyUpsertor
{
    public static string UpsertNestedKey(
        IReadOnlyList<string> lines,
        List<string> newLines,
        string keyLine,
        string[] keyParts)
    {
        var sectionHeader = $"[{keyParts[0]}]";
        var inTargetSection = false;
        var foundSection = false;
        var keyUpdatedNested = false;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            if (TomlCommandUpdaterLineHelpers.IsTargetHeader(trimmed, sectionHeader))
            {
                inTargetSection = true;
                foundSection = true;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && TomlCommandUpdaterLineHelpers.IsAnyTableHeader(trimmed))
            {
                if (!keyUpdatedNested)
                {
                    newLines.Add(keyLine);
                    keyUpdatedNested = true;
                }

                inTargetSection = false;
            }

            if (inTargetSection && TomlCommandUpdaterLineHelpers.IsTomlKeyAssignmentLine(trimmed, keyParts[^1]))
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

        return TomlCommandUpdaterLineHelpers.NormalizeOutputContent(newLines);
    }
}
