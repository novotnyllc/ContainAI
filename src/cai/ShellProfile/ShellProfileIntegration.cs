namespace ContainAI.Cli.Host;

internal static class ShellProfileIntegration
{
    private static readonly ShellProfileIntegrationService Default = new();

    public static string GetProfileDirectoryPath(string homeDirectory)
        => Default.GetProfileDirectoryPath(homeDirectory);

    public static string GetProfileScriptPath(string homeDirectory)
        => Default.GetProfileScriptPath(homeDirectory);

    public static string ResolvePreferredShellProfilePath(string homeDirectory, string? shellPath)
        => Default.ResolvePreferredShellProfilePath(homeDirectory, shellPath);

    public static IReadOnlyList<string> GetCandidateShellProfilePaths(string homeDirectory, string? shellPath)
        => Default.GetCandidateShellProfilePaths(homeDirectory, shellPath);

    public static Task<bool> EnsureProfileScriptAsync(string homeDirectory, string binDirectory, CancellationToken cancellationToken)
        => Default.EnsureProfileScriptAsync(homeDirectory, binDirectory, cancellationToken);

    public static Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
        => Default.EnsureHookInShellProfileAsync(shellProfilePath, cancellationToken);

    public static Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
        => Default.RemoveHookFromShellProfileAsync(shellProfilePath, cancellationToken);

    public static Task<bool> RemoveProfileScriptAsync(string homeDirectory, CancellationToken cancellationToken)
        => Default.RemoveProfileScriptAsync(homeDirectory, cancellationToken);

    public static bool HasHookBlock(string content)
        => Default.HasHookBlock(content);
}
