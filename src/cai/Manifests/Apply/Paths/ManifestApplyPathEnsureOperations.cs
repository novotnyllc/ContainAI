namespace ContainAI.Cli.Host.Manifests.Apply.Paths;

internal static class ManifestApplyPathEnsureOperations
{
    public static void EnsureDirectory(string path)
    {
        RejectSymlink(path);
        if (File.Exists(path))
        {
            throw new InvalidOperationException($"expected directory but found file: {path}");
        }

        Directory.CreateDirectory(path);
    }

    public static void EnsureFile(string path, bool initializeJson)
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

    private static void RejectSymlink(string path)
    {
        if (!ManifestApplySymlinkOperations.IsSymbolicLink(path))
        {
            return;
        }

        throw new InvalidOperationException($"symlink is not allowed for this operation: {path}");
    }
}
