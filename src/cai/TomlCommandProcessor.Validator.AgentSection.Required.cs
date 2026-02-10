namespace ContainAI.Cli.Host;

internal static partial class TomlCommandAgentSectionValidator
{
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
}
