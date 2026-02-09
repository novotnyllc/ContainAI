using System.Text;

namespace ContainAI.Cli.Host;

internal interface IImportTransferOperations
{
    Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken);

    Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken);

    Task<int> ImportManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}

internal sealed class CaiImportTransferOperations : CaiRuntimeSupport
    , IImportTransferOperations
{
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportSymlinkRelinker symlinkRelinker;

    public CaiImportTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new CaiImportPostCopyOperations(standardOutput, standardError),
            new CaiImportSymlinkRelinker(standardOutput, standardError))
    {
    }

    internal CaiImportTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker)
        : base(standardOutput, standardError)
    {
        postCopyOperations = importPostCopyOperations;
        symlinkRelinker = importSymlinkRelinker;
    }

    public Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken)
        => RestoreArchiveImportCoreAsync(volume, archivePath, excludePriv, cancellationToken);

    public Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
        => InitializeImportTargetsCoreAsync(volume, sourceRoot, entries, noSecrets, cancellationToken);

    public Task<int> ImportManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => ImportManifestEntryCoreAsync(
            volume,
            sourceRoot,
            entry,
            excludePriv,
            noExcludes,
            dryRun,
            verbose,
            cancellationToken);

    public Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
        => postCopyOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);

    public Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => ApplyImportOverridesCoreAsync(volume, manifestEntries, noSecrets, dryRun, verbose, cancellationToken);

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

    private async Task<int> InitializeImportTargetsCoreAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        foreach (var entry in entries)
        {
            if (noSecrets && entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                continue;
            }

            var sourcePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
            var sourceExists = Directory.Exists(sourcePath) || File.Exists(sourcePath);
            var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
            var isFile = entry.Flags.Contains('f', StringComparison.Ordinal);
            if (entry.Optional && !sourceExists)
            {
                continue;
            }

            if (isDirectory)
            {
                var command = $"mkdir -p '/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}' && chown -R 1000:1000 '/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}' || true";
                if (entry.Flags.Contains('s', StringComparison.Ordinal))
                {
                    command += $" && chmod 700 '/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}'";
                }

                var ensureDirectory = await DockerCaptureAsync(
                    ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", command],
                    cancellationToken).ConfigureAwait(false);
                if (ensureDirectory.ExitCode != 0)
                {
                    await stderr.WriteLineAsync(ensureDirectory.StandardError.Trim()).ConfigureAwait(false);
                    return 1;
                }

                continue;
            }

            if (!isFile)
            {
                continue;
            }

            if (entry.Optional && !sourceExists)
            {
                continue;
            }

            var ensureFileCommand = new StringBuilder();
            ensureFileCommand.Append($"dest='/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}'; ");
            ensureFileCommand.Append("mkdir -p \"$(dirname \"$dest\")\"; ");
            ensureFileCommand.Append("if [ ! -f \"$dest\" ]; then : > \"$dest\"; fi; ");
            if (entry.Flags.Contains('j', StringComparison.Ordinal))
            {
                ensureFileCommand.Append("if [ ! -s \"$dest\" ]; then printf '{}' > \"$dest\"; fi; ");
            }

            ensureFileCommand.Append("chown 1000:1000 \"$dest\" || true; ");
            if (entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                ensureFileCommand.Append("chmod 600 \"$dest\"; ");
            }

            var ensureFile = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", ensureFileCommand.ToString()],
                cancellationToken).ConfigureAwait(false);
            if (ensureFile.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureFile.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
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
        var sourceAbsolutePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
        var sourceExists = Directory.Exists(sourceAbsolutePath) || File.Exists(sourceAbsolutePath);
        if (!sourceExists)
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

        var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal) && Directory.Exists(sourceAbsolutePath);
        var normalizedSource = entry.Source.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
        var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');

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

        if (isDirectory)
        {
            rsyncArgs.Add($"/source/{normalizedSource.TrimEnd('/')}/");
            rsyncArgs.Add($"/target/{normalizedTarget.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add($"/source/{normalizedSource}");
            rsyncArgs.Add($"/target/{normalizedTarget}");
        }

        var result = await DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
            return 1;
        }

        var postCopyCode = await postCopyOperations.ApplyManifestPostCopyRulesAsync(
            volume,
            entry,
            dryRun,
            verbose,
            cancellationToken).ConfigureAwait(false);
        if (postCopyCode != 0)
        {
            return postCopyCode;
        }

        if (!isDirectory)
        {
            return 0;
        }

        return await symlinkRelinker.RelinkImportedDirectorySymlinksAsync(
            volume,
            sourceAbsolutePath,
            normalizedTarget,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> ApplyImportOverridesCoreAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var overridesDirectory = Path.Combine(ResolveHomeDirectory(), ".config", "containai", "import-overrides");
        if (!Directory.Exists(overridesDirectory))
        {
            return 0;
        }

        var overrideFiles = Directory.EnumerateFiles(overridesDirectory, "*", SearchOption.AllDirectories)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
        foreach (var file in overrideFiles)
        {
            cancellationToken.ThrowIfCancellationRequested();

            if (IsSymbolicLinkPath(file))
            {
                await stderr.WriteLineAsync($"Skipping override symlink: {file}").ConfigureAwait(false);
                continue;
            }

            var relative = Path.GetRelativePath(overridesDirectory, file).Replace("\\", "/", StringComparison.Ordinal);
            if (!relative.StartsWith('.'))
            {
                relative = "." + relative;
            }

            if (!TryMapSourcePathToTarget(relative, manifestEntries, out var mappedTarget, out var mappedFlags))
            {
                if (verbose)
                {
                    await stderr.WriteLineAsync($"Skipping unmapped override path: {relative}").ConfigureAwait(false);
                }

                continue;
            }

            if (noSecrets && mappedFlags.Contains('s', StringComparison.Ordinal))
            {
                if (verbose)
                {
                    await stderr.WriteLineAsync($"Skipping secret override due to --no-secrets: {relative}").ConfigureAwait(false);
                }

                continue;
            }

            if (dryRun)
            {
                await stdout.WriteLineAsync($"[DRY-RUN] Would apply override {relative} -> {mappedTarget}").ConfigureAwait(false);
                continue;
            }

            var command = $"src='/override/{EscapeForSingleQuotedShell(relative.TrimStart('/'))}'; " +
                          $"dest='/target/{EscapeForSingleQuotedShell(mappedTarget)}'; " +
                          "mkdir -p \"$(dirname \"$dest\")\"; cp -f \"$src\" \"$dest\"; chown 1000:1000 \"$dest\" || true";
            var copy = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/target", "-v", $"{overridesDirectory}:/override:ro", "alpine:3.20", "sh", "-lc", command],
                cancellationToken).ConfigureAwait(false);
            if (copy.ExitCode != 0)
            {
                await stderr.WriteLineAsync(copy.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        return 0;
    }

    private static string ResolveRsyncImage()
    {
        var configured = Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
