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

internal sealed class ShellProfileIntegrationService : IShellProfileIntegration
{
    private readonly IShellProfilePathResolver pathResolver;
    private readonly IShellProfileScriptContentGenerator scriptContentGenerator;
    private readonly IShellProfileHookBlockManager hookBlockManager;

    public ShellProfileIntegrationService()
        : this(
            new ShellProfilePathResolver(),
            new ShellProfileScriptContentGenerator(),
            new ShellProfileHookBlockManager())
    {
    }

    internal ShellProfileIntegrationService(
        IShellProfilePathResolver pathResolver,
        IShellProfileScriptContentGenerator scriptContentGenerator,
        IShellProfileHookBlockManager hookBlockManager)
    {
        this.pathResolver = pathResolver ?? throw new ArgumentNullException(nameof(pathResolver));
        this.scriptContentGenerator = scriptContentGenerator ?? throw new ArgumentNullException(nameof(scriptContentGenerator));
        this.hookBlockManager = hookBlockManager ?? throw new ArgumentNullException(nameof(hookBlockManager));
    }

    public string GetProfileDirectoryPath(string homeDirectory)
        => pathResolver.GetProfileDirectoryPath(homeDirectory);

    public string GetProfileScriptPath(string homeDirectory)
        => pathResolver.GetProfileScriptPath(homeDirectory);

    public string ResolvePreferredShellProfilePath(string homeDirectory, string? shellPath)
        => pathResolver.ResolvePreferredShellProfilePath(homeDirectory, shellPath);

    public IReadOnlyList<string> GetCandidateShellProfilePaths(string homeDirectory, string? shellPath)
        => pathResolver.GetCandidateShellProfilePaths(homeDirectory, shellPath);

    public async Task<bool> EnsureProfileScriptAsync(string homeDirectory, string binDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(binDirectory);

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(profileScriptPath)!);

        var script = scriptContentGenerator.BuildProfileScript(homeDirectory, binDirectory);
        if (File.Exists(profileScriptPath))
        {
            var existing = await File.ReadAllTextAsync(profileScriptPath, cancellationToken).ConfigureAwait(false);
            if (string.Equals(existing, script, StringComparison.Ordinal))
            {
                return false;
            }
        }

        await File.WriteAllTextAsync(profileScriptPath, script, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public async Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        var shellProfileDirectory = Path.GetDirectoryName(shellProfilePath);
        if (!string.IsNullOrWhiteSpace(shellProfileDirectory))
        {
            Directory.CreateDirectory(shellProfileDirectory);
        }

        var existing = File.Exists(shellProfilePath)
            ? await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false)
            : string.Empty;
        if (HasHookBlock(existing))
        {
            return false;
        }

        var hookBlock = hookBlockManager.BuildHookBlock();
        var updated = string.IsNullOrWhiteSpace(existing)
            ? hookBlock + Environment.NewLine
            : existing.TrimEnd() + Environment.NewLine + Environment.NewLine + hookBlock + Environment.NewLine;
        await File.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public async Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        if (!File.Exists(shellProfilePath))
        {
            return false;
        }

        var existing = await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false);
        if (!hookBlockManager.TryRemoveHookBlock(existing, out var updated))
        {
            return false;
        }

        await File.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public Task<bool> RemoveProfileScriptAsync(string homeDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        cancellationToken.ThrowIfCancellationRequested();

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        if (!File.Exists(profileScriptPath))
        {
            return Task.FromResult(false);
        }

        File.Delete(profileScriptPath);

        var profileDirectory = GetProfileDirectoryPath(homeDirectory);
        if (Directory.Exists(profileDirectory) && !Directory.EnumerateFileSystemEntries(profileDirectory).Any())
        {
            Directory.Delete(profileDirectory);
        }

        return Task.FromResult(true);
    }

    public bool HasHookBlock(string content)
        => hookBlockManager.HasHookBlock(content);
}

internal static class ShellProfileIntegrationConstants
{
    public const string ShellIntegrationStartMarker = "# >>> ContainAI shell integration >>>";
    public const string ShellIntegrationEndMarker = "# <<< ContainAI shell integration <<<";
    public const string ProfileDirectoryRelativePath = ".config/containai/profile.d";
    public const string ProfileScriptFileName = "containai.sh";
}
