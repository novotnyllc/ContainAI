namespace ContainAI.Cli.Host;

internal static class TomlEnvSectionValidationCoordinator
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
        if (!TomlEnvSectionFieldValidator.TryValidateEnvFile(parser, envTable, out var envFileError, out var envFile))
        {
            return envFileError;
        }

        if (envFile is not null)
        {
            result["env_file"] = envFile;
        }

        if (!TomlEnvSectionFieldValidator.TryValidateFromHost(parser, envTable, out var fromHostError, out var fromHost))
        {
            return fromHostError;
        }

        result["from_host"] = fromHost;
        var importResult = TomlEnvImportValidator.Validate(parser, envTable);
        result["import"] = importResult.ImportValue;
        return new TomlEnvValidationResult(true, result, importResult.Warning, null);
    }
}
