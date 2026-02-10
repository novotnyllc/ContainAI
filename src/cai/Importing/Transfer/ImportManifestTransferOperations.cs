using System.Text;
using ContainAI.Cli.Host.Importing.Symlinks;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestTransferOperations : CaiRuntimeSupport
    , IImportManifestTransferOperations
{
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportSymlinkRelinker symlinkRelinker;

    private readonly record struct ManifestImportPlan(
        string SourceAbsolutePath,
        bool SourceExists,
        bool IsDirectory,
        string NormalizedSource,
        string NormalizedTarget);

    public ImportManifestTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new CaiImportPostCopyOperations(standardOutput, standardError),
            new ImportSymlinkRelinker(standardOutput, standardError))
    {
    }

    internal ImportManifestTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker)
        : base(standardOutput, standardError)
        => (postCopyOperations, symlinkRelinker) = (
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importSymlinkRelinker ?? throw new ArgumentNullException(nameof(importSymlinkRelinker)));

    public async Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        foreach (var entry in entries)
        {
            if (ShouldSkipForNoSecrets(entry, noSecrets))
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
                var ensureDirectory = await DockerCaptureAsync(
                    ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", BuildEnsureDirectoryCommand(entry.Target, IsSecretEntry(entry))],
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

            var ensureFile = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", BuildEnsureFileCommand(entry)],
                cancellationToken).ConfigureAwait(false);
            if (ensureFile.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureFile.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        return 0;
    }

    public async Task<int> ImportManifestEntryAsync(
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

    public Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
        => postCopyOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);

    private async Task<int> ApplyManifestPostCopyAsync(
        string volume,
        ManifestEntry entry,
        ManifestImportPlan importPlan,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
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

        if (!importPlan.IsDirectory)
        {
            return 0;
        }

        return await symlinkRelinker.RelinkImportedDirectorySymlinksAsync(
            volume,
            importPlan.SourceAbsolutePath,
            importPlan.NormalizedTarget,
            cancellationToken).ConfigureAwait(false);
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

    private static ManifestImportPlan CreateManifestImportPlan(string sourceRoot, ManifestEntry entry)
    {
        var sourceAbsolutePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
        var sourceExists = Directory.Exists(sourceAbsolutePath) || File.Exists(sourceAbsolutePath);
        var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal) && Directory.Exists(sourceAbsolutePath);
        return new(
            sourceAbsolutePath,
            sourceExists,
            isDirectory,
            NormalizeManifestPath(entry.Source),
            NormalizeManifestPath(entry.Target));
    }

    private static string NormalizeManifestPath(string path)
        => path.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');

    private static string BuildEnsureDirectoryCommand(string targetPath, bool isSecret)
    {
        var escapedTarget = EscapeForSingleQuotedShell(targetPath);
        var command = $"mkdir -p '/mnt/agent-data/{escapedTarget}' && chown -R 1000:1000 '/mnt/agent-data/{escapedTarget}' || true";
        if (isSecret)
        {
            command += $" && chmod 700 '/mnt/agent-data/{escapedTarget}'";
        }

        return command;
    }

    private static string BuildEnsureFileCommand(ManifestEntry entry)
    {
        var ensureFileCommand = new StringBuilder();
        ensureFileCommand.Append($"dest='/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}'; ");
        ensureFileCommand.Append("mkdir -p \"$(dirname \"$dest\")\"; ");
        ensureFileCommand.Append("if [ ! -f \"$dest\" ]; then : > \"$dest\"; fi; ");
        if (entry.Flags.Contains('j', StringComparison.Ordinal))
        {
            ensureFileCommand.Append("if [ ! -s \"$dest\" ]; then printf '{}' > \"$dest\"; fi; ");
        }

        ensureFileCommand.Append("chown 1000:1000 \"$dest\" || true; ");
        if (IsSecretEntry(entry))
        {
            ensureFileCommand.Append("chmod 600 \"$dest\"; ");
        }

        return ensureFileCommand.ToString();
    }

    private static string ResolveRsyncImage()
    {
        var configured = System.Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }

    private static bool ShouldSkipForNoSecrets(ManifestEntry entry, bool noSecrets)
        => noSecrets && IsSecretEntry(entry);

    private static bool IsSecretEntry(ManifestEntry entry)
        => entry.Flags.Contains('s', StringComparison.Ordinal);
}
