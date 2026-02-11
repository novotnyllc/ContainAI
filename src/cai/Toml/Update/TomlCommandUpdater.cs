namespace ContainAI.Cli.Host;

internal sealed class TomlCommandUpdater : ITomlCommandUpdater
{
    public string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
        => TomlWorkspaceKeyUpdater.UpsertWorkspaceKey(content, workspacePath, key, value);

    public string RemoveWorkspaceKey(string content, string workspacePath, string key)
        => TomlWorkspaceKeyUpdater.RemoveWorkspaceKey(content, workspacePath, key);

    public string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
        => TomlGlobalKeyUpdater.UpsertGlobalKey(content, keyParts, formattedValue);

    public string RemoveGlobalKey(string content, string[] keyParts)
        => TomlGlobalKeyUpdater.RemoveGlobalKey(content, keyParts);
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
