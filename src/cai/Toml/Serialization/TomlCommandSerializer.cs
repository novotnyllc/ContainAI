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
        var normalized = TomlCommandSerializationNormalizer.NormalizeTomlValue(value);
        var builder = new StringBuilder();
        TomlCommandJsonWriter.WriteJsonValue(builder, normalized);
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
}
