namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandExecutionServices
{
    public string? FormatTomlValueForKey(string key, string value)
        => validator.FormatTomlValueForKey(key, value);

    public TomlEnvValidationResult ValidateEnvSection(IReadOnlyDictionary<string, object?> table)
        => validator.ValidateEnvSection(table);

    public TomlAgentValidationResult ValidateAgentSection(IReadOnlyDictionary<string, object?> table, string sourceFile)
        => validator.ValidateAgentSection(table, sourceFile);
}
