namespace ContainAI.Cli.Host;

internal static class TomlCommandAgentStringListValidation
{
    public static bool TryValidate(
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
}
