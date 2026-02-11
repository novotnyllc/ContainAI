namespace ContainAI.Cli.Host;

internal static partial class TomlCommandAgentSectionValidator
{
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
}
