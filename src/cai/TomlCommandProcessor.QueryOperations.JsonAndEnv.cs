namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandQueryExecutor
{
    public TomlCommandResult GetJson(string filePath)
    {
        var load = services.LoadToml(filePath, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        return services.SerializeAsJson(load.Table!);
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
}
