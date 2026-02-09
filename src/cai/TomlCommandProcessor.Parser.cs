using System.Collections;
using System.Globalization;
using System.Text;
using CsToml;

namespace ContainAI.Cli.Host;

internal sealed class TomlCommandParser : ITomlCommandParser
{
    public IReadOnlyDictionary<string, object?> ParseTomlContent(string content)
    {
        var parsed = CsTomlSerializer.Deserialize<IDictionary<object, object>>(Encoding.UTF8.GetBytes(content));
        return ConvertTable(parsed);
    }

    public bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value)
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
            if (!TryGetTable(current, out var currentTable) || !currentTable.TryGetValue(part, out current))
            {
                value = null;
                return false;
            }
        }

        value = current;
        return true;
    }

    public object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath)
    {
        if (!table.TryGetValue("workspace", out var workspaceObj) || !TryGetTable(workspaceObj, out var workspaceTable))
        {
            return new Dictionary<string, object?>(StringComparer.Ordinal);
        }

        if (!workspaceTable.TryGetValue(workspacePath, out var entry) || !TryGetTable(entry, out var workspaceState))
        {
            return new Dictionary<string, object?>(StringComparer.Ordinal);
        }

        return workspaceState;
    }

    public bool TryGetTable(object? value, out IReadOnlyDictionary<string, object?> table)
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

    public bool TryGetList(object? value, out IReadOnlyList<object?> list)
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

    public string GetValueTypeName(object? value) => value?.GetType().Name ?? "null";

    private static Dictionary<string, object?> ConvertTable(IDictionary<object, object> table)
    {
        var normalized = new Dictionary<string, object?>(table.Count, StringComparer.Ordinal);
        foreach (var pair in table)
        {
            var key = pair.Key switch
            {
                string text => text,
                null => string.Empty,
                _ => Convert.ToString(pair.Key, CultureInfo.InvariantCulture) ?? string.Empty,
            };

            normalized[key] = NormalizeParsedTomlValue(pair.Value);
        }

        return normalized;
    }

    private static object? NormalizeParsedTomlValue(object? value)
        => value switch
        {
            null => null,
            IDictionary<object, object> table => ConvertTable(table),
            object?[] array => array.Select(NormalizeParsedTomlValue).ToList(),
            IList list when value is not string => NormalizeParsedList(list),
            _ => value,
        };

    private static List<object?> NormalizeParsedList(IList values)
    {
        var result = new List<object?>(values.Count);
        foreach (var value in values)
        {
            result.Add(NormalizeParsedTomlValue(value));
        }

        return result;
    }
}
