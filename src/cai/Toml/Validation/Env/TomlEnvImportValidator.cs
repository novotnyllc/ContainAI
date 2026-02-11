namespace ContainAI.Cli.Host;

internal static class TomlEnvImportValidator
{
    public static (object ImportValue, string? Warning) Validate(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> envTable)
    {
        if (!envTable.TryGetValue("import", out var importsObj) || importsObj is null)
        {
            return (Array.Empty<string>(), "[WARN] [env].import missing, treating as empty list");
        }

        if (!parser.TryGetList(importsObj, out var importsArray))
        {
            return (Array.Empty<string>(), $"[WARN] [env].import must be a list, got {parser.GetValueTypeName(importsObj)}; treating as empty list");
        }

        var validated = new List<string>(importsArray.Count);
        var warnings = new List<string>();
        for (var index = 0; index < importsArray.Count; index++)
        {
            if (importsArray[index] is not string key)
            {
                warnings.Add($"[WARN] [env].import[{index}] must be a string, got {parser.GetValueTypeName(importsArray[index])}; skipping");
                continue;
            }

            validated.Add(key);
        }

        return warnings.Count > 0
            ? (validated, string.Join('\n', warnings))
            : (validated, null);
    }
}
