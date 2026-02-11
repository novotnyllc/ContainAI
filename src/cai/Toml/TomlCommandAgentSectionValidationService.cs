namespace ContainAI.Cli.Host;

internal static class TomlCommandAgentSectionValidationService
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

        if (!TomlCommandAgentFieldValidation.TryValidateRequiredString(agentTable, "name", sourceFile, out var name, out var nameError))
        {
            return nameError!.Value;
        }

        if (!TomlCommandAgentFieldValidation.TryValidateRequiredString(agentTable, "binary", sourceFile, out var binary, out var binaryError))
        {
            return binaryError!.Value;
        }

        if (!TomlCommandAgentFieldValidation.TryValidateStringList(
                parser,
                agentTable,
                key: "default_args",
                sourceFile,
                requireNonEmptyItems: false,
                out var defaultArgs,
                out var defaultArgsError))
        {
            return defaultArgsError!.Value;
        }

        if (!TomlCommandAgentFieldValidation.TryValidateStringList(
                parser,
                agentTable,
                key: "aliases",
                sourceFile,
                requireNonEmptyItems: true,
                out var aliases,
                out var aliasesError))
        {
            return aliasesError!.Value;
        }

        if (!TomlCommandAgentFieldValidation.TryValidateOptionalBoolean(
                parser,
                agentTable,
                key: "optional",
                sourceFile,
                out var optional,
                out var optionalError))
        {
            return optionalError!.Value;
        }

        return new TomlAgentValidationResult(
            true,
            BuildResult(sourceFile, name, binary, defaultArgs, aliases, optional),
            null);
    }

    private static Dictionary<string, object?> BuildResult(
        string sourceFile,
        string name,
        string binary,
        List<string> defaultArgs,
        List<string> aliases,
        bool optional)
        => new(StringComparer.Ordinal)
        {
            ["source_file"] = sourceFile,
            ["name"] = name,
            ["binary"] = binary,
            ["default_args"] = defaultArgs,
            ["aliases"] = aliases,
            ["optional"] = optional,
        };
}
