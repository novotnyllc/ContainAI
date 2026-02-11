using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiCommandRuntime
{
    public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigListAsync(options, cancellationToken);

    public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigGetAsync(options, cancellationToken);

    public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigSetAsync(options, cancellationToken);

    public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigUnsetAsync(options, cancellationToken);

    public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigResolveVolumeAsync(options, cancellationToken);

    public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunManifestParseAsync(options, cancellationToken);

    public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunManifestGenerateAsync(options, cancellationToken);

    public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunManifestApplyAsync(options, cancellationToken);

    public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunManifestCheckAsync(options, cancellationToken);
}
