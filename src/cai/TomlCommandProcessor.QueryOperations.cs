namespace ContainAI.Cli.Host;

internal sealed class TomlCommandQueryExecutor(TomlCommandExecutionServices services)
{
    public TomlCommandResult GetKey(string filePath, string key)
    {
        var load = services.LoadToml(filePath, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        if (!services.TryGetNestedValue(load.Table!, key, out var value))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        return new TomlCommandResult(0, services.FormatValue(value), string.Empty);
    }

    public TomlCommandResult GetJson(string filePath)
    {
        var load = services.LoadToml(filePath, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        return services.SerializeAsJson(load.Table!);
    }

    public TomlCommandResult Exists(string filePath, string key)
    {
        var load = services.LoadToml(filePath, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        return services.TryGetNestedValue(load.Table!, key, out _)
            ? new TomlCommandResult(0, string.Empty, string.Empty)
            : new TomlCommandResult(1, string.Empty, string.Empty);
    }

    public TomlCommandResult GetEnv(string filePath)
    {
        var load = services.LoadToml(filePath, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        var result = services.ValidateEnvSection(load.Table!);
        if (!result.Success)
        {
            return new TomlCommandResult(1, string.Empty, result.Error!);
        }

        var serialized = services.SerializeJsonValue(result.Value);
        return new TomlCommandResult(0, serialized, result.Warning ?? string.Empty);
    }

    public TomlCommandResult GetWorkspace(string filePath, string workspacePath)
    {
        if (!services.FileExists(filePath))
        {
            return new TomlCommandResult(0, "{}", string.Empty);
        }

        var load = services.LoadToml(filePath, missingFileExitCode: 0, missingFileMessage: "{}");
        if (!load.Success)
        {
            return load.Result;
        }

        var workspaceState = services.GetWorkspaceState(load.Table!, workspacePath);
        return new TomlCommandResult(0, services.SerializeJsonValue(workspaceState), string.Empty);
    }

    public TomlCommandResult EmitAgents(string filePath)
    {
        var load = services.LoadToml(filePath, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        var validation = services.ValidateAgentSection(load.Table!, filePath);
        if (!validation.Success)
        {
            return new TomlCommandResult(1, string.Empty, validation.Error!);
        }

        return new TomlCommandResult(0, services.SerializeJsonValue(validation.Value), string.Empty);
    }
}
