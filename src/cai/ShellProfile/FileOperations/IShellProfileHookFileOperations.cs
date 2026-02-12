namespace ContainAI.Cli.Host;

internal interface IShellProfileHookFileOperations
{
    Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken);

    Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken);
}
