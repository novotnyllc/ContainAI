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
                TomlCommandJsonCompositeWriter.WriteDictionary(builder, dictionary);
                return;
            case IDictionary<string, object?> dictionary:
                TomlCommandJsonCompositeWriter.WriteDictionary(builder, dictionary);
                return;
            case IReadOnlyList<object?> list:
                TomlCommandJsonCompositeWriter.WriteList(builder, list);
                return;
            case IList<object?> list:
                TomlCommandJsonCompositeWriter.WriteList(builder, list);
                return;
            default:
                TomlCommandJsonStringWriter.WriteJsonString(builder, Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty);
                return;
        }
    }
}
