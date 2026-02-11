using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Paths.Utilities;

namespace ContainAI.Cli.Host.RuntimeSupport.Paths;

internal static class CaiRuntimePathHelpers
{
    internal static bool IsSymbolicLinkPath(string path)
        => CaiSymbolicLinkPathDetector.IsSymbolicLinkPath(path);

    internal static bool TryMapSourcePathToTarget(
        string sourceRelativePath,
        IReadOnlyList<ManifestEntry> entries,
        out string targetRelativePath,
        out string flags)
        => CaiManifestPathMapper.TryMapSourcePathToTarget(sourceRelativePath, entries, out targetRelativePath, out flags);

    internal static string EscapeForSingleQuotedShell(string value)
        => CaiShellSingleQuoteEscaper.EscapeForSingleQuotedShell(value);
}
