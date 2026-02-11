using ContainAI.Cli.Host.Toml;

namespace ContainAI.Cli.Host;

internal static class TomlCommandEnvSectionValidator
{
    public static TomlEnvValidationResult Validate(ITomlCommandParser parser, IReadOnlyDictionary<string, object?> table)
        => TomlCommandEnvSectionValidationService.Validate(parser, table);
}
