namespace ContainAI.Cli.Host;

internal sealed class ShellProfileIntegrationService : IShellProfileIntegration
{
    private readonly IShellProfilePathResolver pathResolver;
    private readonly IShellProfileScriptContentGenerator scriptContentGenerator;
    private readonly IShellProfileHookBlockManager hookBlockManager;
    private readonly IShellProfileScriptFileOperations scriptFileOperations;
    private readonly IShellProfileHookFileOperations hookFileOperations;

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
        : this(
            pathResolver,
            scriptContentGenerator,
            hookBlockManager,
            new ShellProfileScriptFileOperations(new ShellProfileFileSystem()),
            new ShellProfileHookFileOperations(new ShellProfileFileSystem(), hookBlockManager))
    {
    }

    internal ShellProfileIntegrationService(
        IShellProfilePathResolver pathResolver,
        IShellProfileScriptContentGenerator scriptContentGenerator,
        IShellProfileHookBlockManager hookBlockManager,
        IShellProfileScriptFileOperations scriptFileOperations,
        IShellProfileHookFileOperations hookFileOperations)
    {
        this.pathResolver = pathResolver ?? throw new ArgumentNullException(nameof(pathResolver));
        this.scriptContentGenerator = scriptContentGenerator ?? throw new ArgumentNullException(nameof(scriptContentGenerator));
        this.hookBlockManager = hookBlockManager ?? throw new ArgumentNullException(nameof(hookBlockManager));
        this.scriptFileOperations = scriptFileOperations ?? throw new ArgumentNullException(nameof(scriptFileOperations));
        this.hookFileOperations = hookFileOperations ?? throw new ArgumentNullException(nameof(hookFileOperations));
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

    public async Task<bool> EnsureProfileScriptAsync(string homeDirectory, string binDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(binDirectory);

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        var script = scriptContentGenerator.BuildProfileScript(homeDirectory, binDirectory);
        return await scriptFileOperations
            .EnsureProfileScriptAsync(profileScriptPath, script, cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        return await hookFileOperations
            .EnsureHookInShellProfileAsync(shellProfilePath, cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        return await hookFileOperations
            .RemoveHookFromShellProfileAsync(shellProfilePath, cancellationToken)
            .ConfigureAwait(false);
    }

    public Task<bool> RemoveProfileScriptAsync(string homeDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        cancellationToken.ThrowIfCancellationRequested();

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        var profileDirectory = GetProfileDirectoryPath(homeDirectory);
        return scriptFileOperations.RemoveProfileScriptAsync(profileDirectory, profileScriptPath, cancellationToken);
    }
}
