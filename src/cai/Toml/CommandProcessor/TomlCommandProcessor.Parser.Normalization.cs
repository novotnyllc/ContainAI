using System.Collections;
using System.Globalization;

namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandParser
{
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
