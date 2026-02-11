namespace ContainAI.Cli.Host.Toml;

internal static class TomlCommandEnvSectionValidationService
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
        if (!TryValidateEnvFile(parser, envTable, out var envFileError, out var envFile))
        {
            return envFileError;
        }

        if (envFile is not null)
        {
            result["env_file"] = envFile;
        }

        if (!TryValidateFromHost(parser, envTable, out var fromHostError, out var fromHost))
        {
            return fromHostError;
        }

        result["from_host"] = fromHost;
        var importResult = ValidateImport(parser, envTable);
        result["import"] = importResult.ImportValue;
        return new TomlEnvValidationResult(true, result, importResult.Warning, null);
    }

    private static bool TryValidateEnvFile(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> envTable,
        out TomlEnvValidationResult error,
        out string? envFile)
    {
        if (envTable.TryGetValue("env_file", out var envFileObj) && envFileObj is not null)
        {
            if (envFileObj is not string value)
            {
                error = new TomlEnvValidationResult(false, null, null, $"Error: [env].env_file must be a string, got {parser.GetValueTypeName(envFileObj)}");
                envFile = null;
                return false;
            }

            envFile = value;
            error = default;
            return true;
        }

        envFile = null;
        error = default;
        return true;
    }

    private static bool TryValidateFromHost(
        ITomlCommandParser parser,
        IReadOnlyDictionary<string, object?> envTable,
        out TomlEnvValidationResult error,
        out bool fromHost)
    {
        if (envTable.TryGetValue("from_host", out var fromHostObj) && fromHostObj is not null)
        {
            if (fromHostObj is not bool value)
            {
                error = new TomlEnvValidationResult(false, null, null, $"Error: [env].from_host must be a boolean, got {parser.GetValueTypeName(fromHostObj)}");
                fromHost = false;
                return false;
            }

            fromHost = value;
            error = default;
            return true;
        }

        fromHost = false;
        error = default;
        return true;
    }

    private static (object ImportValue, string? Warning) ValidateImport(
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
