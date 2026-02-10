using System.Runtime.InteropServices;

namespace ContainAI.Cli.Host.Manifests.Apply;

internal static partial class ManifestApplyPathOperations
{
    public static void SetUnixModeIfSupported(string path, UnixFileMode mode)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return;
        }

        File.SetUnixFileMode(path, mode);
    }

    public static bool IsSymbolicLink(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            return false;
        }

        return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
    }

    public static string? ResolveLinkTarget(string path)
    {
        var info = new FileInfo(path);
        if (string.IsNullOrWhiteSpace(info.LinkTarget))
        {
            return null;
        }

        return Path.IsPathRooted(info.LinkTarget)
            ? Path.GetFullPath(info.LinkTarget)
            : Path.GetFullPath(Path.Combine(Path.GetDirectoryName(path) ?? "/", info.LinkTarget));
    }

    public static void RemovePath(string path)
    {
        if (Directory.Exists(path) && !File.Exists(path))
        {
            Directory.Delete(path, recursive: false);
            return;
        }

        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }

    private static void RejectSymlink(string path)
    {
        if (!IsSymbolicLink(path))
        {
            return;
        }

        throw new InvalidOperationException($"symlink is not allowed for this operation: {path}");
    }
}
