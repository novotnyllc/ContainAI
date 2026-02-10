namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class CaiConfigRuntimeAdapter : ICaiConfigRuntime
{
    private readonly Func<string?, string> resolveConfigPath;
    private readonly Func<string, string> expandHomePath;
    private readonly Func<string, string> normalizeConfigKey;
    private readonly Func<ConfigCommandRequest, string, (string? Workspace, string? Error)> resolveWorkspaceScope;
    private readonly Func<Func<TomlCommandResult>, CancellationToken, Task<TomlProcessResult>> runTomlAsync;
    private readonly Func<string, string?, CancellationToken, Task<string?>> resolveDataVolumeAsync;

    public CaiConfigRuntimeAdapter(
        Func<string?, string> resolveConfigPath,
        Func<string, string> expandHomePath,
        Func<string, string> normalizeConfigKey,
        Func<ConfigCommandRequest, string, (string? Workspace, string? Error)> resolveWorkspaceScope,
        Func<Func<TomlCommandResult>, CancellationToken, Task<TomlProcessResult>> runTomlAsync,
        Func<string, string?, CancellationToken, Task<string?>> resolveDataVolumeAsync)
    {
        this.resolveConfigPath = resolveConfigPath ?? throw new ArgumentNullException(nameof(resolveConfigPath));
        this.expandHomePath = expandHomePath ?? throw new ArgumentNullException(nameof(expandHomePath));
        this.normalizeConfigKey = normalizeConfigKey ?? throw new ArgumentNullException(nameof(normalizeConfigKey));
        this.resolveWorkspaceScope = resolveWorkspaceScope ?? throw new ArgumentNullException(nameof(resolveWorkspaceScope));
        this.runTomlAsync = runTomlAsync ?? throw new ArgumentNullException(nameof(runTomlAsync));
        this.resolveDataVolumeAsync = resolveDataVolumeAsync ?? throw new ArgumentNullException(nameof(resolveDataVolumeAsync));
    }

    public string ResolveConfigPath(string? workspacePath) => resolveConfigPath(workspacePath);

    public string ExpandHomePath(string path) => expandHomePath(path);

    public string NormalizeConfigKey(string key) => normalizeConfigKey(key);

    public (string? Workspace, string? Error) ResolveWorkspaceScope(ConfigCommandRequest request, string normalizedKey) =>
        resolveWorkspaceScope(request, normalizedKey);

    public Task<TomlProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken) =>
        runTomlAsync(operation, cancellationToken);

    public Task<string?> ResolveDataVolumeAsync(string workspace, string? explicitVolume, CancellationToken cancellationToken) =>
        resolveDataVolumeAsync(workspace, explicitVolume, cancellationToken);
}
