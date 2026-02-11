using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ConfigManifest;

namespace ContainAI.Cli.Host;

internal sealed class CaiManifestCommandHandler
{
    private readonly IManifestCommandProcessor manifestCommandProcessor;

    public CaiManifestCommandHandler(IManifestCommandProcessor processor)
        => manifestCommandProcessor = processor ?? throw new ArgumentNullException(nameof(processor));

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
