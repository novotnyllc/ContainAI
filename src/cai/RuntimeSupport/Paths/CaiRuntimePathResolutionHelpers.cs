using ContainAI.Cli.Host.RuntimeSupport.Paths.Resolution;

namespace ContainAI.Cli.Host.RuntimeSupport.Paths;

internal static class CaiRuntimePathResolutionHelpers
{
    internal static bool IsExecutableOnPath(string fileName)
        => CaiExecutablePathProbe.IsExecutableOnPath(fileName);

    internal static Task<string> ResolveChannelAsync(IReadOnlyList<string> configFileNames, CancellationToken cancellationToken)
        => CaiChannelResolver.ResolveChannelAsync(configFileNames, cancellationToken);

    internal static Task<string?> ResolveDataVolumeAsync(
        string workspace,
        string? explicitVolume,
        IReadOnlyList<string> configFileNames,
        CancellationToken cancellationToken)
        => CaiDataVolumeResolver.ResolveDataVolumeAsync(workspace, explicitVolume, configFileNames, cancellationToken);
}
