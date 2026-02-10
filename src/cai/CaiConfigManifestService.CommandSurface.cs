using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ConfigManifest;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host;

internal sealed class CaiConfigManifestService : CaiRuntimeSupport
{
    private readonly IConfigCommandProcessor configCommandProcessor;
    private readonly IManifestCommandProcessor manifestCommandProcessor;

    public CaiConfigManifestService(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ManifestTomlParser())
    {
    }

    internal CaiConfigManifestService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser)
        : this(standardOutput, standardError, manifestTomlParser, new ManifestApplier(manifestTomlParser))
    {
    }

    internal CaiConfigManifestService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IManifestApplier manifestApplier)
        : this(
            standardOutput,
            standardError,
            manifestTomlParser,
            manifestApplier,
            new ConfigCommandProcessor(
                standardOutput,
                standardError,
                new CaiConfigRuntimeAdapter(
                    ResolveConfigPath,
                    ExpandHomePath,
                    NormalizeConfigKey,
                    (request, normalizedKey) =>
                    {
                        var parsed = new ParsedConfigCommand(
                            request.Action,
                            request.Key,
                            request.Value,
                            request.Global,
                            request.Workspace,
                            Error: null);
                        return ResolveWorkspaceScope(parsed, normalizedKey);
                    },
                    async (operation, cancellationToken) =>
                    {
                        var result = await RunTomlAsync(operation, cancellationToken).ConfigureAwait(false);
                        return new TomlProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
                    },
                    ResolveDataVolumeAsync)),
            new ManifestCommandProcessor(
                standardOutput,
                standardError,
                manifestTomlParser,
                manifestApplier,
                new ManifestDirectoryResolver(ExpandHomePath)))
    {
    }

    internal CaiConfigManifestService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IManifestApplier manifestApplier,
        IConfigCommandProcessor configCommandProcessor,
        IManifestCommandProcessor manifestCommandProcessor)
        : base(standardOutput, standardError)
    {
        ArgumentNullException.ThrowIfNull(manifestTomlParser);
        ArgumentNullException.ThrowIfNull(manifestApplier);
        this.configCommandProcessor = configCommandProcessor ?? throw new ArgumentNullException(nameof(configCommandProcessor));
        this.manifestCommandProcessor = manifestCommandProcessor ?? throw new ArgumentNullException(nameof(manifestCommandProcessor));
    }

    public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return configCommandProcessor.RunAsync(
            new ConfigCommandRequest("list", null, null, options.Global, options.Workspace),
            cancellationToken);
    }

    public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return configCommandProcessor.RunAsync(
            new ConfigCommandRequest("get", options.Key, null, options.Global, options.Workspace),
            cancellationToken);
    }

    public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return configCommandProcessor.RunAsync(
            new ConfigCommandRequest("set", options.Key, options.Value, options.Global, options.Workspace),
            cancellationToken);
    }

    public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return configCommandProcessor.RunAsync(
            new ConfigCommandRequest("unset", options.Key, null, options.Global, options.Workspace),
            cancellationToken);
    }

    public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return configCommandProcessor.RunAsync(
            new ConfigCommandRequest("resolve-volume", options.ExplicitVolume, null, false, options.Workspace),
            cancellationToken);
    }

    public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return manifestCommandProcessor.RunParseAsync(
            new ManifestParseRequest(options.ManifestPath, options.IncludeDisabled, options.EmitSourceFile),
            cancellationToken);
    }

    public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return manifestCommandProcessor.RunGenerateAsync(
            new ManifestGenerateRequest(options.Kind, options.ManifestPath, options.OutputPath),
            cancellationToken);
    }

    public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return manifestCommandProcessor.RunApplyAsync(
            new ManifestApplyRequest(
                options.Kind,
                options.ManifestPath,
                options.DataDir ?? "/mnt/agent-data",
                options.HomeDir ?? "/home/agent",
                options.ShimDir ?? "/opt/containai/user-agent-shims",
                options.CaiBinary ?? "/usr/local/bin/cai"),
            cancellationToken);
    }

    public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return manifestCommandProcessor.RunCheckAsync(
            new ManifestCheckRequest(options.ManifestDir),
            cancellationToken);
    }
}
