namespace ContainAI.Cli.Host;

internal static partial class TomlGlobalKeyRemover
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

    private static partial string RemoveRootKey(
        IReadOnlyList<string> lines,
        List<string> newLines,
        string keyPart);

    private static partial string RemoveNestedKey(
        IReadOnlyList<string> lines,
        List<string> newLines,
        string[] keyParts);
}
