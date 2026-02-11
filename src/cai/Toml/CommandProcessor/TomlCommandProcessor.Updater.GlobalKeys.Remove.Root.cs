namespace ContainAI.Cli.Host;

internal static partial class TomlGlobalKeyRemover
{
    private static partial string RemoveRootKey(
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
}
