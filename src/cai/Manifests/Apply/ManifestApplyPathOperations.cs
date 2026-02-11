using ContainAI.Cli.Host.Manifests.Apply.Paths;

namespace ContainAI.Cli.Host.Manifests.Apply;

internal static class ManifestApplyPathOperations
{
    public static void EnsureDirectory(string path) => ManifestApplyPathEnsureOperations.EnsureDirectory(path);

    public static void EnsureFile(string path, bool initializeJson) => ManifestApplyPathEnsureOperations.EnsureFile(path, initializeJson);

    public static string CombineUnderRoot(string root, string relativePath, string fieldName)
        => ManifestApplyRootPathCombiner.CombineUnderRoot(root, relativePath, fieldName);

    public static void SetUnixModeIfSupported(string path, UnixFileMode mode) => ManifestApplyUnixModeOperations.SetUnixModeIfSupported(path, mode);

    public static bool IsSymbolicLink(string path) => ManifestApplySymlinkOperations.IsSymbolicLink(path);

    public static string? ResolveLinkTarget(string path) => ManifestApplySymlinkOperations.ResolveLinkTarget(path);

    public static void RemovePath(string path) => ManifestApplySymlinkOperations.RemovePath(path);
}
