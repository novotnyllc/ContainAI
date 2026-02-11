using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed class ImportSymlinkRelinker : IImportSymlinkRelinker
{
    private readonly TextWriter stderr;
    private readonly IImportSymlinkScanner symlinkScanner;
    private readonly IImportSymlinkRelinkOperationBuilder operationBuilder;
    private readonly IImportSymlinkRelinkShellCommandBuilder commandBuilder;

    public ImportSymlinkRelinker(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportSymlinkScanner(),
            new ImportSymlinkRelinkOperationBuilder(standardError, new PosixPathService()),
            new ImportSymlinkRelinkShellCommandBuilder())
    {
    }

    internal ImportSymlinkRelinker(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportSymlinkScanner symlinkScanner,
        IImportSymlinkRelinkOperationBuilder importSymlinkRelinkOperationBuilder,
        IImportSymlinkRelinkShellCommandBuilder importSymlinkRelinkShellCommandBuilder)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.symlinkScanner = symlinkScanner ?? throw new ArgumentNullException(nameof(symlinkScanner));
        operationBuilder = importSymlinkRelinkOperationBuilder ?? throw new ArgumentNullException(nameof(importSymlinkRelinkOperationBuilder));
        commandBuilder = importSymlinkRelinkShellCommandBuilder ?? throw new ArgumentNullException(nameof(importSymlinkRelinkShellCommandBuilder));
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

        var operations = operationBuilder.Build(sourceDirectoryPath, targetRelativePath, symlinks);
        if (operations.Count == 0)
        {
            return 0;
        }

        var command = commandBuilder.Build(operations);
        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", command],
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
