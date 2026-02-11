namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandExecutionServices
{
    public TomlCommandResult SerializeAsJson(IReadOnlyDictionary<string, object?> table)
        => serializer.SerializeAsJson(table);

    public string SerializeJsonValue(object? value)
        => serializer.SerializeJsonValue(value);

    public string FormatValue(object? value)
        => serializer.FormatValue(value);
}
