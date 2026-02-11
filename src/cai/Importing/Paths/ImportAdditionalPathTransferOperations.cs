using ContainAI.Cli.Host;
using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed class ImportAdditionalPathTransferOperations : IImportAdditionalPathTransferOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public ImportAdditionalPathTransferOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> ImportAdditionalPathAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            await stdout.WriteLineAsync($"[DRY-RUN] Would sync additional path {additionalPath.SourcePath} -> {additionalPath.TargetPath}").ConfigureAwait(false);
            return 0;
        }

        if (verbose && noExcludes)
        {
            await stdout.WriteLineAsync("[INFO] --no-excludes does not disable .priv. filtering for additional paths").ConfigureAwait(false);
        }

        var ensureCommand = additionalPath.IsDirectory
            ? $"mkdir -p '/target/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(additionalPath.TargetPath)}'"
            : $"mkdir -p \"$(dirname '/target/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(additionalPath.TargetPath)}')\"";
        var ensureResult = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", ensureCommand],
            cancellationToken).ConfigureAwait(false);
        if (ensureResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(ensureResult.StandardError))
            {
                await stderr.WriteLineAsync(ensureResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            BuildRsyncArgs(volume, additionalPath),
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            var normalizedError = errorOutput.Trim();
            if (normalizedError.Contains("could not make way for new symlink", StringComparison.OrdinalIgnoreCase) &&
                !normalizedError.Contains("cannot delete non-empty directory", StringComparison.OrdinalIgnoreCase))
            {
                normalizedError += $"{System.Environment.NewLine}cannot delete non-empty directory";
            }

            await stderr.WriteLineAsync(normalizedError).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private static List<string> BuildRsyncArgs(string volume, ImportAdditionalPath additionalPath)
    {
        var rsyncArgs = new List<string>
        {
            "run",
            "--rm",
            "--entrypoint",
            "rsync",
            "-v",
            $"{volume}:/target",
            "-v",
            $"{additionalPath.SourcePath}:/source:ro",
            ResolveRsyncImage(),
            "-a",
        };

        if (additionalPath.ApplyPrivFilter)
        {
            rsyncArgs.Add("--exclude=*.priv.*");
        }

        if (additionalPath.IsDirectory)
        {
            rsyncArgs.Add("/source/");
            rsyncArgs.Add($"/target/{additionalPath.TargetPath.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add("/source");
            rsyncArgs.Add($"/target/{additionalPath.TargetPath}");
        }

        return rsyncArgs;
    }

    private static string ResolveRsyncImage()
    {
        var configured = System.Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
