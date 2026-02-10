namespace ContainAI.Cli.Host;

internal static class TomlCommandEnvSectionValidator
{
    public static TomlEnvValidationResult Validate(ITomlCommandParser parser, IReadOnlyDictionary<string, object?> table)
    {
        if (!table.TryGetValue("env", out var envObj) || envObj is null)
        {
            return new TomlEnvValidationResult(true, null, null, null);
        }

        if (!parser.TryGetTable(envObj, out var envTable))
        {
            return new TomlEnvValidationResult(false, null, null, "Error: [env] section must be a table/dict");
        }

        var result = new Dictionary<string, object?>(StringComparer.Ordinal);
        string? warning = null;

        if (envTable.TryGetValue("env_file", out var envFileObj) && envFileObj is not null)
        {
            if (envFileObj is not string envFile)
            {
                return new TomlEnvValidationResult(false, null, null, $"Error: [env].env_file must be a string, got {parser.GetValueTypeName(envFileObj)}");
            }

            result["env_file"] = envFile;
        }

        if (envTable.TryGetValue("from_host", out var fromHostObj) && fromHostObj is not null)
        {
            if (fromHostObj is not bool fromHost)
            {
                return new TomlEnvValidationResult(false, null, null, $"Error: [env].from_host must be a boolean, got {parser.GetValueTypeName(fromHostObj)}");
            }

            result["from_host"] = fromHost;
        }
        else
        {
            result["from_host"] = false;
        }

        if (!envTable.TryGetValue("import", out var importsObj) || importsObj is null)
        {
            warning = "[WARN] [env].import missing, treating as empty list";
            result["import"] = Array.Empty<string>();
            return new TomlEnvValidationResult(true, result, warning, null);
        }

        if (!parser.TryGetList(importsObj, out var importsArray))
        {
            warning = $"[WARN] [env].import must be a list, got {parser.GetValueTypeName(importsObj)}; treating as empty list";
            result["import"] = Array.Empty<string>();
            return new TomlEnvValidationResult(true, result, warning, null);
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

        result["import"] = validated;
        if (warnings.Count > 0)
        {
            warning = string.Join('\n', warnings);
        }

        return new TomlEnvValidationResult(true, result, warning, null);
    }
}
