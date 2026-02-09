namespace ContainAI.Cli.Host;

internal static partial class TomlCommandProcessor
{
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
}
