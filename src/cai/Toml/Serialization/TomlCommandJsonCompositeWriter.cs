using System.Text;

namespace ContainAI.Cli.Host;

internal static class TomlCommandJsonCompositeWriter
{
    public static void WriteDictionary(StringBuilder builder, IEnumerable<KeyValuePair<string, object?>> dictionary)
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
            TomlCommandJsonWriter.WriteJsonValue(builder, pair.Value);
        }

        builder.Append('}');
    }

    public static void WriteList(StringBuilder builder, IReadOnlyList<object?> list)
    {
        builder.Append('[');
        for (var index = 0; index < list.Count; index++)
        {
            if (index > 0)
            {
                builder.Append(',');
            }

            TomlCommandJsonWriter.WriteJsonValue(builder, list[index]);
        }

        builder.Append(']');
    }

    public static void WriteList(StringBuilder builder, IList<object?> list)
    {
        builder.Append('[');
        for (var index = 0; index < list.Count; index++)
        {
            if (index > 0)
            {
                builder.Append(',');
            }

            TomlCommandJsonWriter.WriteJsonValue(builder, list[index]);
        }

        builder.Append(']');
    }
}
