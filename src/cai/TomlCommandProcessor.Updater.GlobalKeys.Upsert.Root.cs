namespace ContainAI.Cli.Host;

internal static class TomlGlobalRootKeyUpsertor
{
    public static string UpsertRootKey(
        IReadOnlyList<string> lines,
        List<string> newLines,
        string keyLine,
        string keyPart)
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

            if (!inTable && TomlCommandUpdaterLineHelpers.IsTomlKeyAssignmentLine(trimmed, keyPart))
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
}
