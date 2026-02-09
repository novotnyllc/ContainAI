namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandUpdater : ITomlCommandUpdater
{
}

internal static class TomlCommandTextFormatter
{
    public static string FormatTomlString(string value)
    {
        if (value.IndexOfAny(['\n', '\r', '\t', '"', '\\']) >= 0)
        {
            var escaped = value
                .Replace("\\", "\\\\", StringComparison.Ordinal)
                .Replace("\"", "\\\"", StringComparison.Ordinal)
                .Replace("\n", "\\n", StringComparison.Ordinal)
                .Replace("\r", "\\r", StringComparison.Ordinal)
                .Replace("\t", "\\t", StringComparison.Ordinal);
            return $"\"{escaped}\"";
        }

        return $"\"{value}\"";
    }

    public static string EscapeTomlKey(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("\"", "\\\"", StringComparison.Ordinal);
}
