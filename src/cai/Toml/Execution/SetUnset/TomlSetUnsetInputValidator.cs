using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed class TomlSetUnsetInputValidator(
    TomlCommandExecutionServices services,
    Regex workspaceKeyRegex,
    Regex globalKeyRegex)
{
    public TomlCommandResult? ValidateWorkspaceKey(string key)
    {
        if (!workspaceKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        return null;
    }

    public static TomlCommandResult? ValidateWorkspacePathAbsolute(string workspacePath)
    {
        if (!workspacePath.StartsWith('/'))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Workspace path must be absolute: {workspacePath}");
        }

        return null;
    }

    public static TomlCommandResult? ValidateWorkspacePathForSet(string workspacePath)
    {
        if (workspacePath.Contains('\0'))
        {
            return new TomlCommandResult(1, string.Empty, "Error: Workspace path contains null byte");
        }

        if (workspacePath.Contains('\n') || workspacePath.Contains('\r'))
        {
            return new TomlCommandResult(1, string.Empty, "Error: Workspace path contains newline");
        }

        return null;
    }

    public TomlCommandResult? ValidateGlobalKey(string key)
    {
        if (!globalKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        return null;
    }

    public static TomlCommandResult? ValidateGlobalSetKeyParts(string key, out string[] parts)
    {
        parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (parts.Length > 2)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Key nesting too deep (max 2 levels): {key}");
        }

        return null;
    }

    public static TomlCommandResult? ValidateGlobalUnsetKeyParts(string key, out string[] parts)
    {
        parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        return null;
    }

    public TomlCommandResult? ValidateGlobalSetValue(string key, string value, out string formattedValue)
    {
        var maybeFormattedValue = services.FormatTomlValueForKey(key, value);
        if (maybeFormattedValue is null)
        {
            formattedValue = string.Empty;
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid value for key '{key}'");
        }

        formattedValue = maybeFormattedValue;
        return null;
    }
}
