namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandSetUnsetExecutor
{
    public TomlCommandResult SetWorkspaceKey(string filePath, string workspacePath, string key, string value)
    {
        if (!workspaceKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!workspacePath.StartsWith('/'))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Workspace path must be absolute: {workspacePath}");
        }

        if (workspacePath.Contains('\0'))
        {
            return new TomlCommandResult(1, string.Empty, "Error: Workspace path contains null byte");
        }

        if (workspacePath.Contains('\n') || workspacePath.Contains('\r'))
        {
            return new TomlCommandResult(1, string.Empty, "Error: Workspace path contains newline");
        }

        var contentRead = services.TryReadText(filePath, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = services.UpsertWorkspaceKey(content, workspacePath, key, value);
        return services.WriteConfig(filePath, updated);
    }

    public TomlCommandResult UnsetWorkspaceKey(string filePath, string workspacePath, string key)
    {
        if (!workspaceKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!workspacePath.StartsWith('/'))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Workspace path must be absolute: {workspacePath}");
        }

        if (!services.FileExists(filePath))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        var contentRead = services.TryReadText(filePath, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = services.RemoveWorkspaceKey(content, workspacePath, key);
        return services.WriteConfig(filePath, updated);
    }
}
