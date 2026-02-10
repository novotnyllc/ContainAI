using System.Text;
using CsToml;

namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandParser : ITomlCommandParser
{
    public IReadOnlyDictionary<string, object?> ParseTomlContent(string content)
    {
        var parsed = CsTomlSerializer.Deserialize<IDictionary<object, object>>(Encoding.UTF8.GetBytes(content));
        return ConvertTable(parsed);
    }

    public string GetValueTypeName(object? value) => value?.GetType().Name ?? "null";
}
