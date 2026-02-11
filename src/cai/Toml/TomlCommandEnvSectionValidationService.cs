namespace ContainAI.Cli.Host.Toml;

internal static class TomlCommandEnvSectionValidationService
{
    public static TomlEnvValidationResult Validate(ITomlCommandParser parser, IReadOnlyDictionary<string, object?> table)
        => TomlEnvSectionValidationCoordinator.Validate(parser, table);
}
