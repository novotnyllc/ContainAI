namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed partial class ImportSymlinkRelinker : CaiRuntimeSupport
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
}
