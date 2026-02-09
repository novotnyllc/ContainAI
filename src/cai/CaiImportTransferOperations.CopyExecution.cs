namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportTransferOperations
{
    private async Task<int> RestoreArchiveImportCoreAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken)
    {
        var clear = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", "find /mnt/agent-data -mindepth 1 -delete"],
            cancellationToken).ConfigureAwait(false);
        if (clear.ExitCode != 0)
        {
            await stderr.WriteLineAsync(clear.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        var archiveDirectory = Path.GetDirectoryName(archivePath)!;
        var archiveName = Path.GetFileName(archivePath);
        var extractArgs = new List<string>
        {
            "run",
            "--rm",
            "-v",
            $"{volume}:/mnt/agent-data",
            "-v",
            $"{archiveDirectory}:/backup:ro",
            "alpine:3.20",
            "tar",
        };
        if (excludePriv)
        {
            extractArgs.Add("--exclude=./shell/bashrc.d/*.priv.*");
            extractArgs.Add("--exclude=shell/bashrc.d/*.priv.*");
        }

        extractArgs.Add("-xzf");
        extractArgs.Add($"/backup/{archiveName}");
        extractArgs.Add("-C");
        extractArgs.Add("/mnt/agent-data");

        var extract = await DockerCaptureAsync(extractArgs, cancellationToken).ConfigureAwait(false);
        if (extract.ExitCode != 0)
        {
            await stderr.WriteLineAsync(extract.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> ImportManifestEntryCoreAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var importPlan = CreateManifestImportPlan(sourceRoot, entry);
        if (!importPlan.SourceExists)
        {
            if (verbose && !entry.Optional)
            {
                await stderr.WriteLineAsync($"Source not found: {entry.Source}").ConfigureAwait(false);
            }

            return 0;
        }

        if (dryRun)
        {
            await stdout.WriteLineAsync($"[DRY-RUN] Would sync {entry.Source} -> {entry.Target}").ConfigureAwait(false);
            return 0;
        }

        var rsyncArgs = BuildManifestRsyncArguments(volume, sourceRoot, entry, excludePriv, noExcludes, importPlan);
        var copyCode = await ExecuteManifestRsyncAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (copyCode != 0)
        {
            return copyCode;
        }

        return await ApplyManifestPostCopyAsync(volume, entry, importPlan, dryRun, verbose, cancellationToken).ConfigureAwait(false);
    }

    private static List<string> BuildManifestRsyncArguments(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        ManifestImportPlan importPlan)
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
            $"{sourceRoot}:/source:ro",
            ResolveRsyncImage(),
            "-a",
        };

        if (entry.Flags.Contains('m', StringComparison.Ordinal))
        {
            rsyncArgs.Add("--delete");
        }

        if (!noExcludes && entry.Flags.Contains('x', StringComparison.Ordinal))
        {
            rsyncArgs.Add("--exclude=.system/");
        }

        if (!noExcludes && entry.Flags.Contains('p', StringComparison.Ordinal) && excludePriv)
        {
            rsyncArgs.Add("--exclude=*.priv.*");
        }

        if (importPlan.IsDirectory)
        {
            rsyncArgs.Add($"/source/{importPlan.NormalizedSource.TrimEnd('/')}/");
            rsyncArgs.Add($"/target/{importPlan.NormalizedTarget.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add($"/source/{importPlan.NormalizedSource}");
            rsyncArgs.Add($"/target/{importPlan.NormalizedTarget}");
        }

        return rsyncArgs;
    }

    private async Task<int> ExecuteManifestRsyncAsync(IReadOnlyList<string> rsyncArgs, CancellationToken cancellationToken)
    {
        var result = await DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode == 0)
        {
            return 0;
        }

        var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
        await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
        return 1;
    }

    private static string ResolveRsyncImage()
    {
        var configured = Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
