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
