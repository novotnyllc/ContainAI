using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService : CaiRuntimeSupport
{
    public CaiConfigManifestService(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunParsedConfigCommandAsync(
            new ParsedConfigCommand("list", null, null, options.Global, options.Workspace, null),
            cancellationToken);
    }

    public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunParsedConfigCommandAsync(
            new ParsedConfigCommand("get", options.Key, null, options.Global, options.Workspace, null),
            cancellationToken);
    }

    public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunParsedConfigCommandAsync(
            new ParsedConfigCommand("set", options.Key, options.Value, options.Global, options.Workspace, null),
            cancellationToken);
    }

    public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunParsedConfigCommandAsync(
            new ParsedConfigCommand("unset", options.Key, null, options.Global, options.Workspace, null),
            cancellationToken);
    }

    public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunParsedConfigCommandAsync(
            new ParsedConfigCommand("resolve-volume", options.ExplicitVolume, null, false, options.Workspace, null),
            cancellationToken);
    }

    public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunManifestParseCoreAsync(options.ManifestPath, options.IncludeDisabled, options.EmitSourceFile, cancellationToken);
    }

    public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunManifestGenerateCoreAsync(options.Kind, options.ManifestPath, options.OutputPath, cancellationToken);
    }

    public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunManifestApplyCoreAsync(
            options.Kind,
            options.ManifestPath,
            dataDir: options.DataDir ?? "/mnt/agent-data",
            homeDir: options.HomeDir ?? "/home/agent",
            shimDir: options.ShimDir ?? "/opt/containai/user-agent-shims",
            caiBinaryPath: options.CaiBinary ?? "/usr/local/bin/cai",
            cancellationToken);
    }

    public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunManifestCheckCoreAsync(options.ManifestDir, cancellationToken);
    }
}
