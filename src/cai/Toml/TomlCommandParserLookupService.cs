namespace ContainAI.Cli.Host.Toml;

internal static class TomlCommandParserLookupService
{
    public static bool TryGetNestedValue(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> table,
        string key,
        out object? value)
    {
        var parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            value = null;
            return false;
        }

        object? current = table;
        foreach (var part in parts)
        {
            if (!parser.TryGetTable(current, out var currentTable) || !currentTable.TryGetValue(part, out current))
            {
                value = null;
                return false;
            }
        }

        value = current;
        return true;
    }

    public static object GetWorkspaceState(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> table,
        string workspacePath)
    {
        if (!table.TryGetValue("workspace", out var workspaceObj) || !parser.TryGetTable(workspaceObj, out var workspaceTable))
        {
            return new Dictionary<string, object?>(StringComparer.Ordinal);
        }

        if (!workspaceTable.TryGetValue(workspacePath, out var entry) || !parser.TryGetTable(entry, out var workspaceState))
        {
            return new Dictionary<string, object?>(StringComparer.Ordinal);
        }

        return workspaceState;
    }
}
