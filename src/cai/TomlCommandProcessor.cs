using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed record TomlCommandResult(int ExitCode, string StandardOutput, string StandardError);

internal static partial class TomlCommandProcessor
{
    private static readonly Regex WorkspaceKeyRegex = WorkspaceKeyRegexFactory();
    private static readonly Regex GlobalKeyRegex = GlobalKeyRegexFactory();

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

    public static TomlCommandResult SetWorkspaceKey(string filePath, string workspacePath, string key, string value)
        => Execute(
            CreateArguments(filePath) with
            {
                WorkspacePathOrUnsetPath = workspacePath,
                WorkspaceKey = key,
                Value = value,
            },
            ExecuteSetWorkspaceKey);

    public static TomlCommandResult UnsetWorkspaceKey(string filePath, string workspacePath, string key)
        => Execute(
            CreateArguments(filePath) with
            {
                WorkspacePathOrUnsetPath = workspacePath,
                WorkspaceKey = key,
            },
            ExecuteUnsetWorkspaceKey);

    public static TomlCommandResult SetKey(string filePath, string key, string value)
        => Execute(CreateArguments(filePath) with { KeyOrExistsArg = key, Value = value }, ExecuteSetKey);

    public static TomlCommandResult UnsetKey(string filePath, string key)
        => Execute(CreateArguments(filePath) with { KeyOrExistsArg = key }, ExecuteUnsetKey);

    public static TomlCommandResult EmitAgents(string filePath)
        => Execute(CreateArguments(filePath), ExecuteEmitAgents);

    private static TomlCommandResult Execute(TomlCommandArguments arguments, Func<TomlCommandArguments, TomlCommandResult> operation)
    {
        if (string.IsNullOrWhiteSpace(arguments.FilePath))
        {
            return new TomlCommandResult(1, string.Empty, "Error: --file is required");
        }

        return operation(arguments);
    }

    private static TomlCommandArguments CreateArguments(string filePath)
        => new()
        {
            FilePath = filePath,
        };

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

    private static TomlCommandResult ExecuteSetWorkspaceKey(TomlCommandArguments parsed)
    {
        var wsPath = parsed.WorkspacePathOrUnsetPath!;
        var key = parsed.WorkspaceKey!;
        var value = parsed.Value!;

        if (!WorkspaceKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!wsPath.StartsWith('/'))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Workspace path must be absolute: {wsPath}");
        }

        if (wsPath.Contains('\0'))
        {
            return new TomlCommandResult(1, string.Empty, "Error: Workspace path contains null byte");
        }

        if (wsPath.Contains('\n') || wsPath.Contains('\r'))
        {
            return new TomlCommandResult(1, string.Empty, "Error: Workspace path contains newline");
        }

        var contentRead = TryReadText(parsed.FilePath!, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = UpsertWorkspaceKey(content, wsPath, key, value);
        return WriteConfig(parsed.FilePath!, updated);
    }

    private static TomlCommandResult ExecuteUnsetWorkspaceKey(TomlCommandArguments parsed)
    {
        var wsPath = parsed.WorkspacePathOrUnsetPath!;
        var key = parsed.WorkspaceKey!;

        if (!WorkspaceKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!wsPath.StartsWith('/'))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Workspace path must be absolute: {wsPath}");
        }

        if (!FileExists(parsed.FilePath!))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        var contentRead = TryReadText(parsed.FilePath!, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = RemoveWorkspaceKey(content, wsPath, key);
        return WriteConfig(parsed.FilePath!, updated);
    }

    private static TomlCommandResult ExecuteSetKey(TomlCommandArguments parsed)
    {
        var key = parsed.KeyOrExistsArg!;
        var value = parsed.Value!;

        if (!GlobalKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        var parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (parts.Length > 2)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Key nesting too deep (max 2 levels): {key}");
        }

        var formattedValue = FormatTomlValueForKey(key, value);
        if (formattedValue is null)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid value for key '{key}'");
        }

        var contentRead = TryReadText(parsed.FilePath!, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = UpsertGlobalKey(content, parts, formattedValue);
        return WriteConfig(parsed.FilePath!, updated);
    }

    private static TomlCommandResult ExecuteUnsetKey(TomlCommandArguments parsed)
    {
        var key = parsed.KeyOrExistsArg!;
        if (!GlobalKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!FileExists(parsed.FilePath!))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        var parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        var contentRead = TryReadText(parsed.FilePath!, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = RemoveGlobalKey(content, parts);
        return WriteConfig(parsed.FilePath!, updated);
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
