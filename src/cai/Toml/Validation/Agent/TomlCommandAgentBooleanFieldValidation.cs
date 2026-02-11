namespace ContainAI.Cli.Host;

internal static class TomlCommandAgentBooleanFieldValidation
{
    public static bool TryValidateOptionalBoolean(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> table,
        string key,
        string sourceFile,
        out bool value,
        out TomlAgentValidationResult? error)
    {
        value = false;
        if (!table.TryGetValue(key, out var boolObj) || boolObj is null)
        {
            error = null;
            return true;
        }

        if (boolObj is not bool parsed)
        {
            error = new TomlAgentValidationResult(
                false,
                null,
                $"Error: [agent].{key} must be a boolean, got {parser.GetValueTypeName(boolObj)} in {sourceFile}");
            return false;
        }

        value = parsed;
        error = null;
        return true;
    }
}
