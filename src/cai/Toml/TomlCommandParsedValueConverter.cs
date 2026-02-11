using System.Collections;

namespace ContainAI.Cli.Host.Toml;

internal static class TomlCommandParsedValueConverter
{
    public static bool TryGetTable(
        object? value,
        Func<IDictionary<object, object>, Dictionary<string, object?>> convertTable,
        out IReadOnlyDictionary<string, object?> table)
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
                table = convertTable(dictionary);
                return true;
            default:
                table = default!;
                return false;
        }
    }

    public static bool TryGetList(
        object? value,
        Func<IList, List<object?>> normalizeList,
        out IReadOnlyList<object?> list)
    {
        switch (value)
        {
            case IReadOnlyList<object?> readonlyList:
                list = readonlyList;
                return true;
            case IList values when value is not string:
                list = normalizeList(values);
                return true;
            default:
                list = default!;
                return false;
        }
    }
}
