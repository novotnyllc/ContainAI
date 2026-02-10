namespace ContainAI.Cli.Host;

internal static class TomlCommandAgentSectionValidator
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

        if (!agentTable.TryGetValue("name", out var nameObj) || nameObj is not string name || string.IsNullOrEmpty(name))
        {
            return new TomlAgentValidationResult(false, null, $"Error: [agent].name is required in {sourceFile}");
        }

        if (!agentTable.TryGetValue("binary", out var binaryObj) || binaryObj is not string binary || string.IsNullOrEmpty(binary))
        {
            return new TomlAgentValidationResult(false, null, $"Error: [agent].binary is required in {sourceFile}");
        }

        var defaultArgs = new List<string>();
        if (agentTable.TryGetValue("default_args", out var defaultArgsObj) && defaultArgsObj is not null)
        {
            if (!parser.TryGetList(defaultArgsObj, out var defaultArgsArray))
            {
                return new TomlAgentValidationResult(false, null, $"Error: [agent].default_args must be a list, got {parser.GetValueTypeName(defaultArgsObj)} in {sourceFile}");
            }

            for (var index = 0; index < defaultArgsArray.Count; index++)
            {
                if (defaultArgsArray[index] is not string arg)
                {
                    return new TomlAgentValidationResult(false, null, $"Error: [agent].default_args[{index}] must be a string, got {parser.GetValueTypeName(defaultArgsArray[index])} in {sourceFile}");
                }

                defaultArgs.Add(arg);
            }
        }

        var aliases = new List<string>();
        if (agentTable.TryGetValue("aliases", out var aliasesObj) && aliasesObj is not null)
        {
            if (!parser.TryGetList(aliasesObj, out var aliasesArray))
            {
                return new TomlAgentValidationResult(false, null, $"Error: [agent].aliases must be a list, got {parser.GetValueTypeName(aliasesObj)} in {sourceFile}");
            }

            for (var index = 0; index < aliasesArray.Count; index++)
            {
                if (aliasesArray[index] is not string alias || string.IsNullOrEmpty(alias))
                {
                    return new TomlAgentValidationResult(false, null, $"Error: [agent].aliases[{index}] must be a non-empty string in {sourceFile}");
                }

                aliases.Add(alias);
            }
        }

        var optional = false;
        if (agentTable.TryGetValue("optional", out var optionalObj) && optionalObj is not null)
        {
            if (optionalObj is not bool optionalBool)
            {
                return new TomlAgentValidationResult(false, null, $"Error: [agent].optional must be a boolean, got {parser.GetValueTypeName(optionalObj)} in {sourceFile}");
            }

            optional = optionalBool;
        }

        var result = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["source_file"] = sourceFile,
            ["name"] = name,
            ["binary"] = binary,
            ["default_args"] = defaultArgs,
            ["aliases"] = aliases,
            ["optional"] = optional,
        };

        return new TomlAgentValidationResult(true, result, null);
    }
}
