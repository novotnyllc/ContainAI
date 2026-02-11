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

    private static TomlAgentValidationResult? ValidateRequiredAgentString(
        IReadOnlyDictionary<string, object?> agentTable,
        string key,
        string sourceFile,
        out string value)
    {
        if (!agentTable.TryGetValue(key, out var rawValue) || rawValue is not string parsedValue || string.IsNullOrEmpty(parsedValue))
        {
            value = string.Empty;
            return new TomlAgentValidationResult(false, null, $"Error: [agent].{key} is required in {sourceFile}");
        }

        value = parsedValue;
        return null;
    }

    private static TomlAgentValidationResult? ValidateDefaultArgs(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> agentTable,
        string sourceFile,
        out List<string> defaultArgs)
    {
        defaultArgs = new List<string>();
        if (!agentTable.TryGetValue("default_args", out var defaultArgsObj) || defaultArgsObj is null)
        {
            return null;
        }

        if (!parser.TryGetList(defaultArgsObj, out var defaultArgsArray))
        {
            return new TomlAgentValidationResult(
                false,
                null,
                $"Error: [agent].default_args must be a list, got {parser.GetValueTypeName(defaultArgsObj)} in {sourceFile}");
        }

        for (var index = 0; index < defaultArgsArray.Count; index++)
        {
            if (defaultArgsArray[index] is not string arg)
            {
                return new TomlAgentValidationResult(
                    false,
                    null,
                    $"Error: [agent].default_args[{index}] must be a string, got {parser.GetValueTypeName(defaultArgsArray[index])} in {sourceFile}");
            }

            defaultArgs.Add(arg);
        }

        return null;
    }

    private static TomlAgentValidationResult? ValidateAliases(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> agentTable,
        string sourceFile,
        out List<string> aliases)
    {
        aliases = new List<string>();
        if (!agentTable.TryGetValue("aliases", out var aliasesObj) || aliasesObj is null)
        {
            return null;
        }

        if (!parser.TryGetList(aliasesObj, out var aliasesArray))
        {
            return new TomlAgentValidationResult(
                false,
                null,
                $"Error: [agent].aliases must be a list, got {parser.GetValueTypeName(aliasesObj)} in {sourceFile}");
        }

        for (var index = 0; index < aliasesArray.Count; index++)
        {
            if (aliasesArray[index] is not string alias || string.IsNullOrEmpty(alias))
            {
                return new TomlAgentValidationResult(
                    false,
                    null,
                    $"Error: [agent].aliases[{index}] must be a non-empty string in {sourceFile}");
            }

            aliases.Add(alias);
        }

        return null;
    }

    private static TomlAgentValidationResult? ValidateOptional(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> agentTable,
        string sourceFile,
        out bool optional)
    {
        optional = false;
        if (!agentTable.TryGetValue("optional", out var optionalObj) || optionalObj is null)
        {
            return null;
        }

        if (optionalObj is not bool optionalBool)
        {
            return new TomlAgentValidationResult(
                false,
                null,
                $"Error: [agent].optional must be a boolean, got {parser.GetValueTypeName(optionalObj)} in {sourceFile}");
        }

        optional = optionalBool;
        return null;
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
