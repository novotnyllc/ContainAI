using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ConfigManifest;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService
{
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
}
