using System.Text;

namespace ContainAI.Cli.Host;

internal static partial class TomlCommandJsonWriter
{
    private static void WriteJsonDictionary(StringBuilder builder, IReadOnlyDictionary<string, object?> dictionary)
        => WriteJsonDictionaryCore(builder, dictionary);

    private static void WriteJsonDictionary(StringBuilder builder, IDictionary<string, object?> dictionary)
        => WriteJsonDictionaryCore(builder, dictionary);

    private static void WriteJsonList(StringBuilder builder, IReadOnlyList<object?> list)
        => WriteJsonListCore(builder, list);

    private static void WriteJsonList(StringBuilder builder, IList<object?> list)
        => WriteJsonListCore(builder, list);

    private static void WriteJsonDictionaryCore(StringBuilder builder, IEnumerable<KeyValuePair<string, object?>> dictionary)
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

    private static void WriteJsonListCore(StringBuilder builder, IReadOnlyList<object?> list)
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

    private static void WriteJsonListCore(StringBuilder builder, IList<object?> list)
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
