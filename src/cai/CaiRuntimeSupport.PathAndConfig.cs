using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static bool IsExecutableOnPath(string fileName)
        => CaiRuntimePathResolutionHelpers.IsExecutableOnPath(fileName);

    protected static Task<string> ResolveChannelAsync(CancellationToken cancellationToken)
        => CaiRuntimePathResolutionHelpers.ResolveChannelAsync(ConfigFileNames, cancellationToken);

    protected static Task<string?> ResolveDataVolumeAsync(string workspace, string? explicitVolume, CancellationToken cancellationToken)
        => CaiRuntimePathResolutionHelpers.ResolveDataVolumeAsync(workspace, explicitVolume, ConfigFileNames, cancellationToken);

    protected static string ResolveUserConfigPath()
        => CaiRuntimeConfigPathHelpers.ResolveUserConfigPath(ConfigFileNames);

    protected static string? TryFindExistingUserConfigPath()
        => CaiRuntimeConfigPathHelpers.TryFindExistingUserConfigPath(ConfigFileNames);

    protected static string ResolveConfigPath(string? workspacePath)
        => CaiRuntimeConfigPathHelpers.ResolveConfigPath(workspacePath, ConfigFileNames);

    protected static string ResolveTemplatesDirectory()
        => CaiRuntimeConfigPathHelpers.ResolveTemplatesDirectory();

    protected static string ResolveHomeDirectory()
        => CaiRuntimeHomePathHelpers.ResolveHomeDirectory();

    protected static string ExpandHomePath(string path)
        => CaiRuntimeHomePathHelpers.ExpandHomePath(path);

    protected static string? TryFindWorkspaceConfigPath(string? workspacePath)
        => CaiRuntimeWorkspacePathHelpers.TryFindWorkspaceConfigPath(workspacePath, ConfigFileNames);

    protected static bool IsSymbolicLinkPath(string path)
        => CaiRuntimePathHelpers.IsSymbolicLinkPath(path);

    protected static bool TryMapSourcePathToTarget(
        string sourceRelativePath,
        IReadOnlyList<ManifestEntry> entries,
        out string targetRelativePath,
        out string flags)
        => CaiRuntimePathHelpers.TryMapSourcePathToTarget(sourceRelativePath, entries, out targetRelativePath, out flags);

    protected static string EscapeForSingleQuotedShell(string value)
        => CaiRuntimePathHelpers.EscapeForSingleQuotedShell(value);
}
