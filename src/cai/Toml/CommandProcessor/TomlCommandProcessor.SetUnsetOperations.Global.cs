namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandSetUnsetExecutor
{
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
