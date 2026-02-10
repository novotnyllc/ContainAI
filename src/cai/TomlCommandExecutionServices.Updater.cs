namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandExecutionServices
{
    public string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
        => updater.UpsertWorkspaceKey(content, workspacePath, key, value);

    public string RemoveWorkspaceKey(string content, string workspacePath, string key)
        => updater.RemoveWorkspaceKey(content, workspacePath, key);

    public string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
        => updater.UpsertGlobalKey(content, keyParts, formattedValue);

    public string RemoveGlobalKey(string content, string[] keyParts)
        => updater.RemoveGlobalKey(content, keyParts);
}
