namespace ContainAI.Cli.Host;

internal static class TomlGlobalKeyUpdater
{
    public static string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
    {
        var lines = TomlCommandUpdaterLineHelpers.SplitLines(content);
        var newLines = new List<string>(lines.Count + 3);
        var keyLine = $"{keyParts[^1]} = {formattedValue}";

        if (keyParts.Length == 1)
        {
            var keyUpdated = false;
            var inTable = false;

            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (TomlCommandUpdaterLineHelpers.IsAnyTableHeader(trimmed))
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

                if (!inTable && TomlCommandUpdaterLineHelpers.IsTomlKeyAssignmentLine(trimmed, keyParts[0]))
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
                    var insertAt = newLines.FindIndex(static line => TomlCommandUpdaterLineHelpers.IsAnyTableHeader(line.Trim()));
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

            return TomlCommandUpdaterLineHelpers.NormalizeOutputContent(newLines);
        }

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

    public static string RemoveGlobalKey(string content, string[] keyParts)
    {
        var lines = TomlCommandUpdaterLineHelpers.SplitLines(content);
        var newLines = new List<string>(lines.Count);

        if (keyParts.Length == 1)
        {
            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (!TomlCommandUpdaterLineHelpers.IsAnyTableHeader(trimmed) && TomlCommandUpdaterLineHelpers.IsTomlKeyAssignmentLine(trimmed, keyParts[0]))
                {
                    continue;
                }

                newLines.Add(line);
            }

            return TomlCommandUpdaterLineHelpers.NormalizeOutputContent(newLines);
        }

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
