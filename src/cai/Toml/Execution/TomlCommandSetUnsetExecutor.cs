using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed class TomlCommandSetUnsetExecutor
{
    private readonly TomlWorkspaceSetUnsetExecutor workspaceExecutor;
    private readonly TomlGlobalSetUnsetExecutor globalExecutor;

    public TomlCommandSetUnsetExecutor(
        TomlCommandExecutionServices services,
        Regex workspaceKeyRegex,
        Regex globalKeyRegex)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(workspaceKeyRegex);
        ArgumentNullException.ThrowIfNull(globalKeyRegex);

        var inputValidator = new TomlSetUnsetInputValidator(services, workspaceKeyRegex, globalKeyRegex);
        var contentCoordinator = new TomlSetUnsetContentCoordinator(services);

        workspaceExecutor = new TomlWorkspaceSetUnsetExecutor(services, inputValidator, contentCoordinator);
        globalExecutor = new TomlGlobalSetUnsetExecutor(services, inputValidator, contentCoordinator);
    }

    public TomlCommandResult SetWorkspaceKey(string filePath, string workspacePath, string key, string value)
        => workspaceExecutor.SetWorkspaceKey(filePath, workspacePath, key, value);

    public TomlCommandResult UnsetWorkspaceKey(string filePath, string workspacePath, string key)
        => workspaceExecutor.UnsetWorkspaceKey(filePath, workspacePath, key);

    public TomlCommandResult SetKey(string filePath, string key, string value)
        => globalExecutor.SetKey(filePath, key, value);

    public TomlCommandResult UnsetKey(string filePath, string key)
        => globalExecutor.UnsetKey(filePath, key);
}
