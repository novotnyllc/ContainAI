using System.Collections;
using System.Globalization;

namespace ContainAI.Cli.Host;

internal static class TomlCommandSerializationNormalizer
{
    public static object? NormalizeTomlValue(object? value)
        => value switch
        {
            null => null,
            IReadOnlyDictionary<string, object?> table => table.ToDictionary(static pair => pair.Key, static pair => NormalizeTomlValue(pair.Value), StringComparer.Ordinal),
            IDictionary<string, object?> dictionary => dictionary.ToDictionary(static pair => pair.Key, static pair => NormalizeTomlValue(pair.Value), StringComparer.Ordinal),
            IReadOnlyList<object?> list => list.Select(NormalizeTomlValue).ToList(),
            IList list when value is not string => NormalizeParsedList(list).Select(NormalizeTomlValue).ToList(),
            DateTime dateTime => dateTime.ToString("O", CultureInfo.InvariantCulture),
            DateTimeOffset dateTimeOffset => dateTimeOffset.ToString("O", CultureInfo.InvariantCulture),
            DateOnly dateOnly => dateOnly.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            TimeOnly timeOnly => timeOnly.ToString("HH:mm:ss.fffffff", CultureInfo.InvariantCulture),
            _ => value,
        };

    private static object? NormalizeParsedValue(object? value)
        => value switch
        {
            null => null,
            IDictionary<object, object> table => ConvertObjectTable(table),
            object?[] array => array.Select(NormalizeParsedValue).ToList(),
            IList list when value is not string => NormalizeParsedList(list),
            _ => value,
        };

    private static List<object?> NormalizeParsedList(IList values)
    {
        var result = new List<object?>(values.Count);
        foreach (var value in values)
        {
            result.Add(NormalizeParsedValue(value));
        }

        return result;
    }

    private static Dictionary<string, object?> ConvertObjectTable(IDictionary<object, object> table)
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

            normalized[key] = NormalizeParsedValue(pair.Value);
        }

        return normalized;
    }
}
