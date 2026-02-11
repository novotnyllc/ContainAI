using System.Collections;
using System.Globalization;
using System.Text;
using CsToml;
using ContainAI.Cli.Host.Toml;

namespace ContainAI.Cli.Host;

internal sealed class TomlCommandParser : ITomlCommandParser
{
    public IReadOnlyDictionary<string, object?> ParseTomlContent(string content)
    {
        var parsed = CsTomlSerializer.Deserialize<IDictionary<object, object>>(Encoding.UTF8.GetBytes(content));
        return ConvertTable(parsed);
    }

    public bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value)
        => TomlCommandParserLookupService.TryGetNestedValue(this, table, key, out value);

    public object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath)
        => TomlCommandParserLookupService.GetWorkspaceState(this, table, workspacePath);

    public bool TryGetTable(object? value, out IReadOnlyDictionary<string, object?> table)
        => TomlCommandParsedValueConverter.TryGetTable(value, ConvertTable, out table);

    public bool TryGetList(object? value, out IReadOnlyList<object?> list)
        => TomlCommandParsedValueConverter.TryGetList(value, NormalizeParsedList, out list);

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
