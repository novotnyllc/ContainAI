namespace ContainAI.Cli.Host;

internal static partial class TomlCommandAgentSectionValidator
{
    public static TomlAgentValidationResult Validate(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> table,
        string sourceFile)
    {
        if (!table.TryGetValue("agent", out var agentObj) || agentObj is null)
        {
            return new TomlAgentValidationResult(true, null, null);
        }

        if (!parser.TryGetTable(agentObj, out var agentTable))
        {
            return new TomlAgentValidationResult(false, null, $"Error: [agent] section must be a table/dict in {sourceFile}");
        }

        var nameError = ValidateRequiredAgentString(agentTable, "name", sourceFile, out var name);
        if (nameError is not null)
        {
            return nameError.Value;
        }

        var binaryError = ValidateRequiredAgentString(agentTable, "binary", sourceFile, out var binary);
        if (binaryError is not null)
        {
            return binaryError.Value;
        }

        var defaultArgsError = ValidateDefaultArgs(parser, agentTable, sourceFile, out var defaultArgs);
        if (defaultArgsError is not null)
        {
            return defaultArgsError.Value;
        }

        var aliasesError = ValidateAliases(parser, agentTable, sourceFile, out var aliases);
        if (aliasesError is not null)
        {
            return aliasesError.Value;
        }

        var optionalError = ValidateOptional(parser, agentTable, sourceFile, out var optional);
        if (optionalError is not null)
        {
            return optionalError.Value;
        }

        return new TomlAgentValidationResult(
            true,
            BuildResult(sourceFile, name, binary, defaultArgs, aliases, optional),
            null);
    }
}
