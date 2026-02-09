using System.Collections;
using System.Globalization;
using System.Text;

namespace ContainAI.Cli.Host;

internal sealed class TomlCommandSerializer : ITomlCommandSerializer
{
    public TomlCommandResult SerializeAsJson(IReadOnlyDictionary<string, object?> table)
    {
        try
        {
            return new TomlCommandResult(0, SerializeJsonValue(table), string.Empty);
        }
        catch (ArgumentException ex)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Cannot serialize config: {ex.Message}");
        }
        catch (InvalidOperationException ex)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Cannot serialize config: {ex.Message}");
        }
    }

    public string SerializeJsonValue(object? value)
    {
        var normalized = NormalizeTomlValue(value);
        var builder = new StringBuilder();
        WriteJsonValue(builder, normalized);
        return builder.ToString();
    }

    public string FormatValue(object? value) => value switch
    {
        null => string.Empty,
        bool boolValue => boolValue ? "true" : "false",
        byte or sbyte or short or ushort or int or uint or long or ulong => Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty,
        float or double or decimal => Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty,
        string stringValue => stringValue,
        _ => SerializeJsonValue(value),
    };

    private static object? NormalizeTomlValue(object? value) => value switch
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

    private static void WriteJsonValue(StringBuilder builder, object? value)
    {
        switch (value)
        {
            case null:
                builder.Append("null");
                return;
            case bool boolValue:
                builder.Append(boolValue ? "true" : "false");
                return;
            case byte or sbyte or short or ushort or int or uint or long or ulong or float or double or decimal:
                builder.Append(Convert.ToString(value, CultureInfo.InvariantCulture));
                return;
            case string stringValue:
                WriteJsonString(builder, stringValue);
                return;
            case IReadOnlyDictionary<string, object?> dictionary:
                builder.Append('{');
                var firstProperty = true;
                foreach (var pair in dictionary)
                {
                    if (!firstProperty)
                    {
                        builder.Append(',');
                    }

                    firstProperty = false;
                    WriteJsonString(builder, pair.Key);
                    builder.Append(':');
                    WriteJsonValue(builder, pair.Value);
                }

                builder.Append('}');
                return;
            case IDictionary<string, object?> dictionary:
                builder.Append('{');
                var firstPropertyInDictionary = true;
                foreach (var pair in dictionary)
                {
                    if (!firstPropertyInDictionary)
                    {
                        builder.Append(',');
                    }

                    firstPropertyInDictionary = false;
                    WriteJsonString(builder, pair.Key);
                    builder.Append(':');
                    WriteJsonValue(builder, pair.Value);
                }

                builder.Append('}');
                return;
            case IReadOnlyList<object?> list:
                builder.Append('[');
                for (var index = 0; index < list.Count; index++)
                {
                    if (index > 0)
                    {
                        builder.Append(',');
                    }

                    WriteJsonValue(builder, list[index]);
                }

                builder.Append(']');
                return;
            case IList<object?> list:
                builder.Append('[');
                for (var index = 0; index < list.Count; index++)
                {
                    if (index > 0)
                    {
                        builder.Append(',');
                    }

                    WriteJsonValue(builder, list[index]);
                }

                builder.Append(']');
                return;
            default:
                WriteJsonString(builder, Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty);
                return;
        }
    }

    private static void WriteJsonString(StringBuilder builder, string value)
    {
        builder.Append('"');
        foreach (var ch in value)
        {
            switch (ch)
            {
                case '"':
                    builder.Append("\\\"");
                    break;
                case '\\':
                    builder.Append("\\\\");
                    break;
                case '\b':
                    builder.Append("\\b");
                    break;
                case '\f':
                    builder.Append("\\f");
                    break;
                case '\n':
                    builder.Append("\\n");
                    break;
                case '\r':
                    builder.Append("\\r");
                    break;
                case '\t':
                    builder.Append("\\t");
                    break;
                default:
                    if (ch < 0x20)
                    {
                        builder.Append("\\u");
                        builder.Append(((int)ch).ToString("x4", CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        builder.Append(ch);
                    }

                    break;
            }
        }

        builder.Append('"');
    }
}
