using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed class ImportAdditionalPathTransferOperations : CaiRuntimeSupport
    , IImportAdditionalPathTransferOperations
{
    public ImportAdditionalPathTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
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
            ? $"mkdir -p '/target/{EscapeForSingleQuotedShell(additionalPath.TargetPath)}'"
            : $"mkdir -p \"$(dirname '/target/{EscapeForSingleQuotedShell(additionalPath.TargetPath)}')\"";
        var ensureResult = await DockerCaptureAsync(
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

        var result = await DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
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

    private static string ResolveRsyncImage()
    {
        var configured = System.Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
