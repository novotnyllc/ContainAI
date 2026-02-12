namespace ContainAI.Cli.Host;

internal interface IShellProfileHookBlockManager
{
    bool HasHookBlock(string content);

    string BuildHookBlock();

    bool TryRemoveHookBlock(string content, out string updated);
}
