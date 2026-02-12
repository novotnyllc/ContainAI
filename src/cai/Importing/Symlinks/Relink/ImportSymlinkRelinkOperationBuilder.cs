using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Symlinks;

internal readonly record struct ImportSymlinkRelinkOperation(string LinkPath, string RelativeTarget);

internal sealed class ImportSymlinkRelinkOperationBuilder(
    TextWriter standardError,
    IPosixPathService posixPathService) : IImportSymlinkRelinkOperationBuilder
{
    public IReadOnlyList<ImportSymlinkRelinkOperation> Build(
        string sourceDirectoryPath,
        string targetRelativePath,
        IReadOnlyList<ImportSymlink> symlinks)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceDirectoryPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(targetRelativePath);
        ArgumentNullException.ThrowIfNull(symlinks);

        var operations = new List<ImportSymlinkRelinkOperation>();
        foreach (var symlink in symlinks)
        {
            if (!Path.IsPathRooted(symlink.Target))
            {
                continue;
            }

            var absoluteTarget = Path.GetFullPath(symlink.Target);
            if (!posixPathService.IsPathWithinDirectory(absoluteTarget, sourceDirectoryPath))
            {
                standardError.WriteLine($"[WARN] preserving external absolute symlink: {symlink.RelativePath} -> {symlink.Target}");
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
            operations.Add(new ImportSymlinkRelinkOperation(posixPathService.NormalizePosixPath(volumeLinkPath), relativeTarget));
        }

        return operations;
    }
}
