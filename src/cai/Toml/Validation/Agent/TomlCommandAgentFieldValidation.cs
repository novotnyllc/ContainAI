namespace ContainAI.Cli.Host;

internal static class TomlCommandAgentFieldValidation
{
    public static bool TryValidateRequiredString(
        IReadOnlyDictionary<string, object?> table,
        string key,
        string sourceFile,
        out string value,
        out TomlAgentValidationResult? error)
    {
        if (!table.TryGetValue(key, out var rawValue) || rawValue is not string parsedValue || string.IsNullOrEmpty(parsedValue))
        {
            value = string.Empty;
            error = new TomlAgentValidationResult(false, null, $"Error: [agent].{key} is required in {sourceFile}");
            return false;
        }

        value = parsedValue;
        error = null;
        return true;
    }

    public static bool TryValidateStringList(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> table,
        string key,
        string sourceFile,
        bool requireNonEmptyItems,
        out List<string> values,
        out TomlAgentValidationResult? error)
        => TomlCommandAgentStringListValidation.TryValidate(
            parser,
            table,
            key,
            sourceFile,
            requireNonEmptyItems,
            out values,
            out error);

    public static bool TryValidateOptionalBoolean(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> table,
        string key,
        string sourceFile,
        out bool value,
        out TomlAgentValidationResult? error)
        => TomlCommandAgentBooleanFieldValidation.TryValidateOptionalBoolean(
            parser,
            table,
            key,
            sourceFile,
            out value,
            out error);
}
