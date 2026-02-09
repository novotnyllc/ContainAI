using System.Globalization;

namespace ContainAI.Cli.Host;

internal sealed class TomlCommandValidator(ITomlCommandParser parser) : ITomlCommandValidator
{
    private static readonly HashSet<string> PortKeys =
    [
        "port_range_start",
        "port_range_end",
        "ssh.port_range_start",
        "ssh.port_range_end",
    ];

    private static readonly HashSet<string> BoolKeys =
    [
        "forward_agent",
        "auto_prompt",
        "exclude_priv",
        "ssh.forward_agent",
        "import.auto_prompt",
        "import.exclude_priv",
    ];

    public TomlEnvValidationResult ValidateEnvSection(IReadOnlyDictionary<string, object?> table)
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

    public TomlAgentValidationResult ValidateAgentSection(IReadOnlyDictionary<string, object?> table, string sourceFile)
    {
        if (!table.TryGetValue("agent", out var agentObj) || agentObj is null)
        {
            return new TomlAgentValidationResult(true, null, null);
        }

        if (!parser.TryGetTable(agentObj, out var agentTable))
        {
            return new TomlAgentValidationResult(false, null, $"Error: [agent] section must be a table/dict in {sourceFile}");
        }

        if (!agentTable.TryGetValue("name", out var nameObj) || nameObj is not string name || string.IsNullOrEmpty(name))
        {
            return new TomlAgentValidationResult(false, null, $"Error: [agent].name is required in {sourceFile}");
        }

        if (!agentTable.TryGetValue("binary", out var binaryObj) || binaryObj is not string binary || string.IsNullOrEmpty(binary))
        {
            return new TomlAgentValidationResult(false, null, $"Error: [agent].binary is required in {sourceFile}");
        }

        var defaultArgs = new List<string>();
        if (agentTable.TryGetValue("default_args", out var defaultArgsObj) && defaultArgsObj is not null)
        {
            if (!parser.TryGetList(defaultArgsObj, out var defaultArgsArray))
            {
                return new TomlAgentValidationResult(false, null, $"Error: [agent].default_args must be a list, got {parser.GetValueTypeName(defaultArgsObj)} in {sourceFile}");
            }

            for (var index = 0; index < defaultArgsArray.Count; index++)
            {
                if (defaultArgsArray[index] is not string arg)
                {
                    return new TomlAgentValidationResult(false, null, $"Error: [agent].default_args[{index}] must be a string, got {parser.GetValueTypeName(defaultArgsArray[index])} in {sourceFile}");
                }

                defaultArgs.Add(arg);
            }
        }

        var aliases = new List<string>();
        if (agentTable.TryGetValue("aliases", out var aliasesObj) && aliasesObj is not null)
        {
            if (!parser.TryGetList(aliasesObj, out var aliasesArray))
            {
                return new TomlAgentValidationResult(false, null, $"Error: [agent].aliases must be a list, got {parser.GetValueTypeName(aliasesObj)} in {sourceFile}");
            }

            for (var index = 0; index < aliasesArray.Count; index++)
            {
                if (aliasesArray[index] is not string alias || string.IsNullOrEmpty(alias))
                {
                    return new TomlAgentValidationResult(false, null, $"Error: [agent].aliases[{index}] must be a non-empty string in {sourceFile}");
                }

                aliases.Add(alias);
            }
        }

        var optional = false;
        if (agentTable.TryGetValue("optional", out var optionalObj) && optionalObj is not null)
        {
            if (optionalObj is not bool optionalBool)
            {
                return new TomlAgentValidationResult(false, null, $"Error: [agent].optional must be a boolean, got {parser.GetValueTypeName(optionalObj)} in {sourceFile}");
            }

            optional = optionalBool;
        }

        var result = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["source_file"] = sourceFile,
            ["name"] = name,
            ["binary"] = binary,
            ["default_args"] = defaultArgs,
            ["aliases"] = aliases,
            ["optional"] = optional,
        };

        return new TomlAgentValidationResult(true, result, null);
    }

    public string? FormatTomlValueForKey(string key, string value)
    {
        var keyName = key.Contains('.', StringComparison.Ordinal)
            ? key[(key.LastIndexOf('.') + 1)..]
            : key;

        if (PortKeys.Contains(key) || PortKeys.Contains(keyName))
        {
            if (!int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var port))
            {
                return null;
            }

            if (port is < 1024 or > 65535)
            {
                return null;
            }

            return port.ToString(CultureInfo.InvariantCulture);
        }

        if (BoolKeys.Contains(key) || BoolKeys.Contains(keyName))
        {
            return value.ToLowerInvariant() switch
            {
                "true" or "1" or "yes" => "true",
                "false" or "0" or "no" => "false",
                _ => null,
            };
        }

        return TomlCommandTextFormatter.FormatTomlString(value);
    }
}
