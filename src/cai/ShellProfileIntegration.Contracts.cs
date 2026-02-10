namespace ContainAI.Cli.Host;

internal interface IShellProfileIntegration
{
    string GetProfileDirectoryPath(string homeDirectory);

    string GetProfileScriptPath(string homeDirectory);

    string ResolvePreferredShellProfilePath(string homeDirectory, string? shellPath);

    IReadOnlyList<string> GetCandidateShellProfilePaths(string homeDirectory, string? shellPath);

    Task<bool> EnsureProfileScriptAsync(string homeDirectory, string binDirectory, CancellationToken cancellationToken);

    Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken);

    Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken);

    Task<bool> RemoveProfileScriptAsync(string homeDirectory, CancellationToken cancellationToken);

    bool HasHookBlock(string content);
}
