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
    {
        values = new List<string>();
        if (!table.TryGetValue(key, out var listObj) || listObj is null)
        {
            error = null;
            return true;
        }

        if (!parser.TryGetList(listObj, out var listValues))
        {
            error = new TomlAgentValidationResult(
                false,
                null,
                $"Error: [agent].{key} must be a list, got {parser.GetValueTypeName(listObj)} in {sourceFile}");
            return false;
        }

        for (var index = 0; index < listValues.Count; index++)
        {
            if (listValues[index] is not string item)
            {
                error = new TomlAgentValidationResult(
                    false,
                    null,
                    $"Error: [agent].{key}[{index}] must be a string, got {parser.GetValueTypeName(listValues[index])} in {sourceFile}");
                return false;
            }

            if (requireNonEmptyItems && string.IsNullOrEmpty(item))
            {
                error = new TomlAgentValidationResult(
                    false,
                    null,
                    $"Error: [agent].{key}[{index}] must be a non-empty string in {sourceFile}");
                return false;
            }

            values.Add(item);
        }

        error = null;
        return true;
    }

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
