using System.Globalization;
using System.Text;

namespace ContainAI.Cli.Host;

internal static class TomlCommandJsonWriter
{
    public static void WriteJsonValue(StringBuilder builder, object? value)
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
                TomlCommandJsonStringWriter.WriteJsonString(builder, stringValue);
                return;
            case IReadOnlyDictionary<string, object?> dictionary:
                WriteJsonDictionary(builder, dictionary);
                return;
            case IDictionary<string, object?> dictionary:
                WriteJsonDictionary(builder, dictionary);
                return;
            case IReadOnlyList<object?> list:
                WriteJsonList(builder, list);
                return;
            case IList<object?> list:
                WriteJsonList(builder, list);
                return;
            default:
                TomlCommandJsonStringWriter.WriteJsonString(builder, Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty);
                return;
        }
    }

    private static void WriteJsonDictionary(StringBuilder builder, IReadOnlyDictionary<string, object?> dictionary)
    {
        builder.Append('{');
        var firstProperty = true;
        foreach (var pair in dictionary)
        {
            if (!firstProperty)
            {
                builder.Append(',');
            }

            firstProperty = false;
            TomlCommandJsonStringWriter.WriteJsonString(builder, pair.Key);
            builder.Append(':');
            WriteJsonValue(builder, pair.Value);
        }

        builder.Append('}');
    }

    private static void WriteJsonDictionary(StringBuilder builder, IDictionary<string, object?> dictionary)
    {
        builder.Append('{');
        var firstProperty = true;
        foreach (var pair in dictionary)
        {
            if (!firstProperty)
            {
                builder.Append(',');
            }

            firstProperty = false;
            TomlCommandJsonStringWriter.WriteJsonString(builder, pair.Key);
            builder.Append(':');
            WriteJsonValue(builder, pair.Value);
        }

        builder.Append('}');
    }

    private static void WriteJsonList(StringBuilder builder, IReadOnlyList<object?> list)
    {
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
    }

    private static void WriteJsonList(StringBuilder builder, IList<object?> list)
    {
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
    }
}
