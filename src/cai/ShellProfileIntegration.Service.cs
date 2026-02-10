namespace ContainAI.Cli.Host;

internal sealed partial class ShellProfileIntegrationService : IShellProfileIntegration
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

    public bool HasHookBlock(string content)
        => hookBlockManager.HasHookBlock(content);
}
