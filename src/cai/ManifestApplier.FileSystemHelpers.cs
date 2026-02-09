using System.Runtime.InteropServices;

namespace ContainAI.Cli.Host;

internal static partial class ManifestApplier
{
    private static void EnsureDirectory(string path)
    {
        RejectSymlink(path);
        if (File.Exists(path))
        {
            throw new InvalidOperationException($"expected directory but found file: {path}");
        }

        Directory.CreateDirectory(path);
    }

    private static void EnsureFile(string path, bool initializeJson)
    {
        RejectSymlink(path);

        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            EnsureDirectory(directory);
        }

        if (Directory.Exists(path))
        {
            throw new InvalidOperationException($"expected file but found directory: {path}");
        }

        using (File.Open(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.Read))
        {
        }

        if (initializeJson)
        {
            var info = new FileInfo(path);
            if (info.Length == 0)
            {
                File.WriteAllText(path, "{}");
            }
        }
    }

    private static void SetUnixModeIfSupported(string path, UnixFileMode mode)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return;
        }

        File.SetUnixFileMode(path, mode);
    }

    private static string CombineUnderRoot(string root, string relativePath, string fieldName)
    {
        if (Path.IsPathRooted(relativePath))
        {
            throw new InvalidOperationException($"{fieldName} must be relative: {relativePath}");
        }

        var combined = Path.GetFullPath(Path.Combine(root, relativePath));
        if (string.Equals(combined, root, StringComparison.Ordinal))
        {
            return combined;
        }

        if (!combined.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{fieldName} escapes root: {relativePath}");
        }

        return combined;
    }

    private static bool IsSymbolicLink(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            return false;
        }

        return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
    }

    private static string? ResolveLinkTarget(string path)
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

    private static void RejectSymlink(string path)
    {
        if (!IsSymbolicLink(path))
        {
            return;
        }

        throw new InvalidOperationException($"symlink is not allowed for this operation: {path}");
    }

    private static void RemovePath(string path)
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
}
