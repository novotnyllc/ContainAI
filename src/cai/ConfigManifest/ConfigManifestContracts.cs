namespace ContainAI.Cli.Host.ConfigManifest;

internal readonly record struct ConfigCommandRequest(
    string Action,
    string? Key,
    string? Value,
    bool Global,
    string? Workspace);

internal readonly record struct ManifestParseRequest(
    string ManifestPath,
    bool IncludeDisabled,
    bool EmitSourceFile);

internal readonly record struct ManifestGenerateRequest(
    string Kind,
    string ManifestPath,
    string? OutputPath);

internal readonly record struct ManifestApplyRequest(
    string Kind,
    string ManifestPath,
    string DataDir,
    string HomeDir,
    string ShimDir,
    string CaiBinaryPath);

internal readonly record struct ManifestCheckRequest(string? ManifestDirectory);

internal readonly record struct TomlProcessResult(
    int ExitCode,
    string StandardOutput,
    string StandardError);

internal interface ICaiConfigRuntime
{
    string ResolveConfigPath(string? workspacePath);

    string ExpandHomePath(string path);

    string NormalizeConfigKey(string key);

    (string? Workspace, string? Error) ResolveWorkspaceScope(ConfigCommandRequest request, string normalizedKey);

    Task<TomlProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken);

    Task<string?> ResolveDataVolumeAsync(string workspace, string? explicitVolume, CancellationToken cancellationToken);
}

internal interface IManifestDirectoryResolver
{
    string ResolveManifestDirectory(string? userProvidedPath);
}

internal interface IConfigCommandProcessor
{
    Task<int> RunAsync(ConfigCommandRequest request, CancellationToken cancellationToken);
}

internal interface IManifestCommandProcessor
{
    Task<int> RunParseAsync(ManifestParseRequest request, CancellationToken cancellationToken);

    Task<int> RunGenerateAsync(ManifestGenerateRequest request, CancellationToken cancellationToken);

    Task<int> RunApplyAsync(ManifestApplyRequest request, CancellationToken cancellationToken);

    Task<int> RunCheckAsync(ManifestCheckRequest request, CancellationToken cancellationToken);
}
