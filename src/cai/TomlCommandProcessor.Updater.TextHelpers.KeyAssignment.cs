namespace ContainAI.Cli.Host;

internal static partial class TomlCommandUpdaterLineHelpers
{
    public static bool IsTomlKeyAssignmentLine(string trimmedLine, string key)
    {
        if (string.IsNullOrWhiteSpace(trimmedLine) || string.IsNullOrWhiteSpace(key))
        {
            return false;
        }

        var line = trimmedLine.AsSpan();
        var keySpan = key.AsSpan();
        if (!line.StartsWith(keySpan, StringComparison.Ordinal))
        {
            return false;
        }

        var position = keySpan.Length;
        while (position < line.Length && char.IsWhiteSpace(line[position]))
        {
            position++;
        }

        return position < line.Length && line[position] == '=';
    }
}
