namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandQueryExecutor
{
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
