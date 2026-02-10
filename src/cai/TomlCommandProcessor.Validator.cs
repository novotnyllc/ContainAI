namespace ContainAI.Cli.Host;

internal sealed class TomlCommandValidator(ITomlCommandParser parser) : ITomlCommandValidator
{
    public TomlEnvValidationResult ValidateEnvSection(IReadOnlyDictionary<string, object?> table)
        => TomlCommandEnvSectionValidator.Validate(parser, table);

    public TomlAgentValidationResult ValidateAgentSection(IReadOnlyDictionary<string, object?> table, string sourceFile)
        => TomlCommandAgentSectionValidator.Validate(parser, table, sourceFile);

    public string? FormatTomlValueForKey(string key, string value)
        => TomlCommandValueFormatter.FormatTomlValueForKey(key, value);
}
