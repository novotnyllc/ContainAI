using System.Collections;

namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandParser
{
    public bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value)
        => TomlCommandParserLookupCollaborator.TryGetNestedValue(this, table, key, out value);

    public object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath)
        => TomlCommandParserLookupCollaborator.GetWorkspaceState(this, table, workspacePath);

    public bool TryGetTable(object? value, out IReadOnlyDictionary<string, object?> table)
        => TomlCommandParserLookupCollaborator.TryGetTable(value, out table);

    public bool TryGetList(object? value, out IReadOnlyList<object?> list)
        => TomlCommandParserLookupCollaborator.TryGetList(value, out list);

    private static class TomlCommandParserLookupCollaborator
    {
        public static bool TryGetNestedValue(TomlCommandParser parser, IReadOnlyDictionary<string, object?> table, string key, out object? value)
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

        public static object GetWorkspaceState(TomlCommandParser parser, IReadOnlyDictionary<string, object?> table, string workspacePath)
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

        public static bool TryGetTable(object? value, out IReadOnlyDictionary<string, object?> table)
        {
            switch (value)
            {
                case IReadOnlyDictionary<string, object?> readonlyTable:
                    table = readonlyTable;
                    return true;
                case IDictionary<string, object?> dictionary:
                    table = dictionary.ToDictionary(static pair => pair.Key, static pair => pair.Value, StringComparer.Ordinal);
                    return true;
                case IDictionary<object, object> dictionary:
                    table = ConvertTable(dictionary);
                    return true;
                default:
                    table = default!;
                    return false;
            }
        }

        public static bool TryGetList(object? value, out IReadOnlyList<object?> list)
        {
            switch (value)
            {
                case IReadOnlyList<object?> readonlyList:
                    list = readonlyList;
                    return true;
                case IList values when value is not string:
                    list = NormalizeParsedList(values);
                    return true;
                default:
                    list = default!;
                    return false;
            }
        }
    }
}
