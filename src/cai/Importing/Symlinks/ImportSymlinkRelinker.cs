using System.Text;

namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed class ImportSymlinkRelinker : CaiRuntimeSupport
    , IImportSymlinkRelinker
{
    private readonly IImportSymlinkScanner symlinkScanner;
    private readonly IPosixPathService posixPathService;

    public ImportSymlinkRelinker(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ImportSymlinkScanner(), new PosixPathService())
    {
    }

    internal ImportSymlinkRelinker(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportSymlinkScanner symlinkScanner,
        IPosixPathService posixPathService)
        : base(standardOutput, standardError)
    {
        this.symlinkScanner = symlinkScanner ?? throw new ArgumentNullException(nameof(symlinkScanner));
        this.posixPathService = posixPathService ?? throw new ArgumentNullException(nameof(posixPathService));
    }

    public async Task<int> RelinkImportedDirectorySymlinksAsync(
        string volume,
        string sourceDirectoryPath,
        string targetRelativePath,
        CancellationToken cancellationToken)
    {
        var symlinks = symlinkScanner.CollectSymlinksForRelink(sourceDirectoryPath);
        if (symlinks.Count == 0)
        {
            return 0;
        }

        var operations = BuildSymlinkOperations(sourceDirectoryPath, targetRelativePath, symlinks);
        if (operations.Count == 0)
        {
            return 0;
        }

        var commandBuilder = BuildRelinkShellCommand(operations);
        var result = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", commandBuilder.ToString()],
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

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

    private static StringBuilder BuildRelinkShellCommand(IReadOnlyList<(string LinkPath, string RelativeTarget)> operations)
    {
        var commandBuilder = new StringBuilder();
        foreach (var operation in operations)
        {
            commandBuilder.Append("link='");
            commandBuilder.Append(EscapeForSingleQuotedShell(operation.LinkPath));
            commandBuilder.Append("'; ");
            commandBuilder.Append("mkdir -p \"$(dirname \"$link\")\"; ");
            commandBuilder.Append("rm -rf -- \"$link\"; ");
            commandBuilder.Append("ln -sfn -- '");
            commandBuilder.Append(EscapeForSingleQuotedShell(operation.RelativeTarget));
            commandBuilder.Append("' \"$link\"; ");
        }

        return commandBuilder;
    }
}
