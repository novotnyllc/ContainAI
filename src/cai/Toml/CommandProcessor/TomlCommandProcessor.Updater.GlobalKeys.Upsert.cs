namespace ContainAI.Cli.Host;

internal static class TomlGlobalKeyUpsertor
{
    public static string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
    {
        var lines = TomlCommandUpdaterLineHelpers.SplitLines(content);
        var newLines = new List<string>(lines.Count + 3);
        var keyLine = $"{keyParts[^1]} = {formattedValue}";

        if (keyParts.Length == 1)
        {
            return TomlGlobalRootKeyUpsertor.UpsertRootKey(lines, newLines, keyLine, keyParts[0]);
        }

        return TomlGlobalNestedKeyUpsertor.UpsertNestedKey(lines, newLines, keyLine, keyParts);
    }
}
