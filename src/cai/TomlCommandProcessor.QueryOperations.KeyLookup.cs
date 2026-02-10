namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandQueryExecutor
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
}
