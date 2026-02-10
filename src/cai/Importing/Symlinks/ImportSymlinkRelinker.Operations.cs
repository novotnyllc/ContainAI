namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed partial class ImportSymlinkRelinker
{
    private List<(string LinkPath, string RelativeTarget)> BuildSymlinkOperations(
        string sourceDirectoryPath,
        string targetRelativePath,
        IReadOnlyList<ImportSymlink> symlinks)
    {
        var operations = new List<(string LinkPath, string RelativeTarget)>();
        foreach (var symlink in symlinks)
        {
            if (!Path.IsPathRooted(symlink.Target))
            {
                continue;
            }

            var absoluteTarget = Path.GetFullPath(symlink.Target);
            if (!posixPathService.IsPathWithinDirectory(absoluteTarget, sourceDirectoryPath))
            {
                stderr.WriteLine($"[WARN] preserving external absolute symlink: {symlink.RelativePath} -> {symlink.Target}");
                continue;
            }

            if (!File.Exists(absoluteTarget) && !Directory.Exists(absoluteTarget))
            {
                continue;
            }

            var sourceRelativeTarget = Path.GetRelativePath(sourceDirectoryPath, absoluteTarget).Replace('\\', '/');
            var volumeLinkPath = $"/target/{targetRelativePath.TrimEnd('/')}/{symlink.RelativePath.TrimStart('/')}";
            var volumeTargetPath = $"/target/{targetRelativePath.TrimEnd('/')}/{sourceRelativeTarget.TrimStart('/')}";
            var volumeParentPath = posixPathService.NormalizePosixPath(Path.GetDirectoryName(volumeLinkPath)?.Replace('\\', '/') ?? "/target");
            var relativeTarget = posixPathService.ComputeRelativePosixPath(volumeParentPath, posixPathService.NormalizePosixPath(volumeTargetPath));
            operations.Add((posixPathService.NormalizePosixPath(volumeLinkPath), relativeTarget));
        }

        return operations;
    }
}
