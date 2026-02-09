namespace ContainAI.Cli.Host;

internal static partial class TomlCommandProcessor
{
    public static TomlCommandResult GetKey(string filePath, string key)
        => Execute(CreateArguments(filePath) with { KeyOrExistsArg = key }, ExecuteKey);

    public static TomlCommandResult GetJson(string filePath)
        => Execute(CreateArguments(filePath), ExecuteJson);

    public static TomlCommandResult Exists(string filePath, string key)
        => Execute(CreateArguments(filePath) with { KeyOrExistsArg = key }, ExecuteExists);

    public static TomlCommandResult GetEnv(string filePath)
        => Execute(CreateArguments(filePath), ExecuteEnv);

    public static TomlCommandResult GetWorkspace(string filePath, string workspacePath)
        => Execute(CreateArguments(filePath) with { WorkspacePathOrUnsetPath = workspacePath }, ExecuteGetWorkspace);

    public static TomlCommandResult EmitAgents(string filePath)
        => Execute(CreateArguments(filePath), ExecuteEmitAgents);

    private static TomlCommandResult ExecuteKey(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        var key = parsed.KeyOrExistsArg!;
        if (!TryGetNestedValue(load.Table!, key, out var value))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        return new TomlCommandResult(0, FormatValue(value), string.Empty);
    }

    private static TomlCommandResult ExecuteJson(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        return SerializeAsJson(load.Table!);
    }

    private static TomlCommandResult ExecuteExists(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        return TryGetNestedValue(load.Table!, parsed.KeyOrExistsArg!, out _)
            ? new TomlCommandResult(0, string.Empty, string.Empty)
            : new TomlCommandResult(1, string.Empty, string.Empty);
    }

    private static TomlCommandResult ExecuteEnv(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        var result = ValidateEnvSection(load.Table!);
        if (!result.Success)
        {
            return new TomlCommandResult(1, string.Empty, result.Error!);
        }

        var serialized = SerializeJsonValue(result.Value);
        return new TomlCommandResult(0, serialized, result.Warning ?? string.Empty);
    }

    private static TomlCommandResult ExecuteGetWorkspace(TomlCommandArguments parsed)
    {
        var path = parsed.WorkspacePathOrUnsetPath!;
        var filePath = parsed.FilePath!;

        if (!FileExists(filePath))
        {
            return new TomlCommandResult(0, "{}", string.Empty);
        }

        var load = LoadToml(filePath, missingFileExitCode: 0, missingFileMessage: "{}");
        if (!load.Success)
        {
            return load.Result;
        }

        var workspaceState = GetWorkspaceState(load.Table!, path);
        return new TomlCommandResult(0, SerializeJsonValue(workspaceState), string.Empty);
    }

    private static TomlCommandResult ExecuteEmitAgents(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        var validation = ValidateAgentSection(load.Table!, parsed.FilePath!);
        if (!validation.Success)
        {
            return new TomlCommandResult(1, string.Empty, validation.Error!);
        }

        return new TomlCommandResult(0, SerializeJsonValue(validation.Value), string.Empty);
    }
}
