using ContainAI.Cli.Host.Toml;

namespace ContainAI.Cli.Host;

internal static class TomlCommandAgentSectionValidator
{
    public static TomlAgentValidationResult Validate(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> table,
        string sourceFile)
        => TomlCommandAgentSectionValidationService.Validate(parser, table, sourceFile);
}
