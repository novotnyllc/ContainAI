using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed class TomlCommandSetUnsetExecutor(
    TomlCommandExecutionServices services,
    Regex workspaceKeyRegex,
    Regex globalKeyRegex)
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

    public TomlCommandResult SetKey(string filePath, string key, string value)
    {
        if (!globalKeyRegex.IsMatch(key))
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

        var formattedValue = services.FormatTomlValueForKey(key, value);
        if (formattedValue is null)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid value for key '{key}'");
        }

        var contentRead = services.TryReadText(filePath, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = services.UpsertGlobalKey(content, parts, formattedValue);
        return services.WriteConfig(filePath, updated);
    }

    public TomlCommandResult UnsetKey(string filePath, string key)
    {
        if (!globalKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!services.FileExists(filePath))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        var parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        var contentRead = services.TryReadText(filePath, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = services.RemoveGlobalKey(content, parts);
        return services.WriteConfig(filePath, updated);
    }
}
