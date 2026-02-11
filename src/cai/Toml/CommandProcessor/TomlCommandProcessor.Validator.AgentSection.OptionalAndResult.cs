namespace ContainAI.Cli.Host;

internal static partial class TomlCommandAgentSectionValidator
{
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
        => new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["source_file"] = sourceFile,
            ["name"] = name,
            ["binary"] = binary,
            ["default_args"] = defaultArgs,
            ["aliases"] = aliases,
            ["optional"] = optional,
        };
}
