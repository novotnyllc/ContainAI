namespace ContainAI.Cli.Host;

internal static class TomlEnvSectionFieldValidator
{
    public static bool TryValidateEnvFile(
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

    public static bool TryValidateFromHost(
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
}
