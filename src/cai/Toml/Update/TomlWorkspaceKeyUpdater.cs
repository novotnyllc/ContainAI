namespace ContainAI.Cli.Host;

internal static class TomlWorkspaceKeyUpdater
{
    public static string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
        => TomlWorkspaceKeyUpsertor.UpsertWorkspaceKey(content, workspacePath, key, value);

    public static string RemoveWorkspaceKey(string content, string workspacePath, string key)
        => TomlWorkspaceKeyRemover.RemoveWorkspaceKey(content, workspacePath, key);
}
