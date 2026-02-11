using ContainAI.Cli.Host.Toml;

namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandParser
{
    public bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value)
        => TomlCommandParserLookupService.TryGetNestedValue(this, table, key, out value);

    public object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath)
        => TomlCommandParserLookupService.GetWorkspaceState(this, table, workspacePath);

    public bool TryGetTable(object? value, out IReadOnlyDictionary<string, object?> table)
        => TomlCommandParsedValueConverter.TryGetTable(value, ConvertTable, out table);

    public bool TryGetList(object? value, out IReadOnlyList<object?> list)
        => TomlCommandParsedValueConverter.TryGetList(value, NormalizeParsedList, out list);
}
