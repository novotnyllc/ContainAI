using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportService : CaiRuntimeSupport
{
    private async Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken)
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

    private async Task<int> InitializeImportTargetsAsync(
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

                var ensureDir = await DockerCaptureAsync(
                    ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", command],
                    cancellationToken).ConfigureAwait(false);
                if (ensureDir.ExitCode != 0)
                {
                    await stderr.WriteLineAsync(ensureDir.StandardError.Trim()).ConfigureAwait(false);
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

    private async Task<int> ImportManifestEntryAsync(
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

        var postCopyCode = await ApplyManifestPostCopyRulesAsync(
            volume,
            entry,
            dryRun,
            verbose,
            cancellationToken).ConfigureAwait(false);
        if (postCopyCode != 0)
        {
            return postCopyCode;
        }

        if (isDirectory)
        {
            var symlinkCode = await RelinkImportedDirectorySymlinksAsync(
                volume,
                sourceAbsolutePath,
                normalizedTarget,
                cancellationToken).ConfigureAwait(false);
            if (symlinkCode != 0)
            {
                return symlinkCode;
            }
        }

        return 0;
    }

    private async Task<int> RelinkImportedDirectorySymlinksAsync(
        string volume,
        string sourceDirectoryPath,
        string targetRelativePath,
        CancellationToken cancellationToken)
    {
        var symlinks = CollectSymlinksForRelink(sourceDirectoryPath);
        if (symlinks.Count == 0)
        {
            return 0;
        }

        var operations = new List<(string LinkPath, string RelativeTarget)>();
        foreach (var symlink in symlinks)
        {
            if (!Path.IsPathRooted(symlink.Target))
            {
                continue;
            }

            var absoluteTarget = Path.GetFullPath(symlink.Target);
            if (!IsPathWithinDirectory(absoluteTarget, sourceDirectoryPath))
            {
                await stderr.WriteLineAsync($"[WARN] preserving external absolute symlink: {symlink.RelativePath} -> {symlink.Target}").ConfigureAwait(false);
                continue;
            }

            if (!File.Exists(absoluteTarget) && !Directory.Exists(absoluteTarget))
            {
                // Preserve broken internal links as-is so import does not silently rewrite them.
                continue;
            }

            var sourceRelativeTarget = Path.GetRelativePath(sourceDirectoryPath, absoluteTarget).Replace('\\', '/');
            var volumeLinkPath = $"/target/{targetRelativePath.TrimEnd('/')}/{symlink.RelativePath.TrimStart('/')}";
            var volumeTargetPath = $"/target/{targetRelativePath.TrimEnd('/')}/{sourceRelativeTarget.TrimStart('/')}";
            var volumeParentPath = NormalizePosixPath(Path.GetDirectoryName(volumeLinkPath)?.Replace('\\', '/') ?? "/target");
            var relativeTarget = ComputeRelativePosixPath(volumeParentPath, NormalizePosixPath(volumeTargetPath));
            operations.Add((NormalizePosixPath(volumeLinkPath), relativeTarget));
        }

        if (operations.Count == 0)
        {
            return 0;
        }

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

    private static List<ImportedSymlink> CollectSymlinksForRelink(string sourceDirectoryPath)
    {
        var symlinks = new List<ImportedSymlink>();
        var stack = new Stack<string>();
        stack.Push(sourceDirectoryPath);
        while (stack.Count > 0)
        {
            var currentDirectory = stack.Pop();
            IEnumerable<string> entries;
            try
            {
                entries = Directory.EnumerateFileSystemEntries(currentDirectory);
            }
            catch (IOException)
            {
                continue;
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (NotSupportedException)
            {
                continue;
            }
            catch (ArgumentException)
            {
                continue;
            }

            foreach (var entry in entries)
            {
                if (IsSymbolicLinkPath(entry))
                {
                    var linkTarget = ReadSymlinkTarget(entry);
                    if (!string.IsNullOrWhiteSpace(linkTarget))
                    {
                        var relativePath = Path.GetRelativePath(sourceDirectoryPath, entry).Replace('\\', '/');
                        symlinks.Add(new ImportedSymlink(relativePath, linkTarget));
                    }

                    continue;
                }

                if (Directory.Exists(entry))
                {
                    stack.Push(entry);
                }
            }
        }

        return symlinks;
    }

    private static string? ReadSymlinkTarget(string path)
    {
        try
        {
            var fileInfo = new FileInfo(path);
            if (!string.IsNullOrWhiteSpace(fileInfo.LinkTarget))
            {
                return fileInfo.LinkTarget;
            }
        }
        catch (IOException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }

        try
        {
            var directoryInfo = new DirectoryInfo(path);
            if (!string.IsNullOrWhiteSpace(directoryInfo.LinkTarget))
            {
                return directoryInfo.LinkTarget;
            }
        }
        catch (IOException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }

        return null;
    }

    private static string NormalizePosixPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return "/";
        }

        var normalized = path.Replace('\\', '/');
        normalized = normalized.Replace("//", "/", StringComparison.Ordinal);
        return string.IsNullOrWhiteSpace(normalized) ? "/" : normalized;
    }

    private static string ComputeRelativePosixPath(string fromDirectory, string toPath)
    {
        var fromParts = NormalizePosixPath(fromDirectory).Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var toParts = NormalizePosixPath(toPath).Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var maxShared = Math.Min(fromParts.Length, toParts.Length);
        var shared = 0;
        while (shared < maxShared && string.Equals(fromParts[shared], toParts[shared], StringComparison.Ordinal))
        {
            shared++;
        }

        var segments = new List<string>();
        for (var index = shared; index < fromParts.Length; index++)
        {
            segments.Add("..");
        }

        for (var index = shared; index < toParts.Length; index++)
        {
            segments.Add(toParts[index]);
        }

        return segments.Count == 0 ? "." : string.Join('/', segments);
    }

    private async Task<int> ApplyManifestPostCopyRulesAsync(
        string volume,
        ManifestEntry entry,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            return 0;
        }

        var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
        if (entry.Flags.Contains('g', StringComparison.Ordinal))
        {
            var gitFilterCode = await ApplyGitConfigFilterAsync(volume, normalizedTarget, verbose, cancellationToken).ConfigureAwait(false);
            if (gitFilterCode != 0)
            {
                return gitFilterCode;
            }
        }

        if (!entry.Flags.Contains('s', StringComparison.Ordinal))
        {
            return 0;
        }

        var chmodMode = entry.Flags.Contains('d', StringComparison.Ordinal) ? "700" : "600";
        var chmodCommand = $"target='/target/{EscapeForSingleQuotedShell(normalizedTarget)}'; " +
                           "if [ -e \"$target\" ]; then chmod " + chmodMode + " \"$target\"; fi; " +
                           "if [ -e \"$target\" ]; then chown 1000:1000 \"$target\" || true; fi";
        var chmodResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", chmodCommand],
            cancellationToken).ConfigureAwait(false);
        if (chmodResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(chmodResult.StandardError))
            {
                await stderr.WriteLineAsync(chmodResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        return 0;
    }

    private async Task<int> ApplyGitConfigFilterAsync(
        string volume,
        string targetRelativePath,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var filterScript = $"target='/target/{EscapeForSingleQuotedShell(targetRelativePath)}'; " +
                           "if [ ! -f \"$target\" ]; then exit 0; fi; " +
                           "tmp=\"$target.tmp\"; " +
                           "awk '\n" +
                           "BEGIN { section=\"\" }\n" +
                           "/^[[:space:]]*\\[[^]]+\\][[:space:]]*$/ {\n" +
                           "  section=$0;\n" +
                           "  gsub(/^[[:space:]]*\\[/, \"\", section);\n" +
                           "  gsub(/\\][[:space:]]*$/, \"\", section);\n" +
                           "  section=tolower(section);\n" +
                           "  print $0;\n" +
                           "  next;\n" +
                           "}\n" +
                           "{\n" +
                           "  lower=tolower($0);\n" +
                           "  if (section==\"credential\" && lower ~ /^[[:space:]]*helper[[:space:]]*=/) next;\n" +
                           "  if ((section==\"commit\" || section==\"tag\") && lower ~ /^[[:space:]]*gpgsign[[:space:]]*=/) next;\n" +
                           "  if (section==\"gpg\" && (lower ~ /^[[:space:]]*program[[:space:]]*=/ || lower ~ /^[[:space:]]*format[[:space:]]*=/)) next;\n" +
                           "  if (section==\"user\" && lower ~ /^[[:space:]]*signingkey[[:space:]]*=/) next;\n" +
                           "  print $0;\n" +
                           "}\n" +
                           "' \"$target\" > \"$tmp\"; " +
                           "mv \"$tmp\" \"$target\"; " +
                           "if ! grep -Eiq \"^[[:space:]]*directory[[:space:]]*=[[:space:]]*/home/agent/workspace[[:space:]]*$\" \"$target\"; then " +
                           "  printf '\\n[safe]\\n\\tdirectory = /home/agent/workspace\\n' >> \"$target\"; " +
                           "fi; " +
                           "chown 1000:1000 \"$target\" || true";

        var filterResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", filterScript],
            cancellationToken).ConfigureAwait(false);
        if (filterResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(filterResult.StandardError))
            {
                await stderr.WriteLineAsync(filterResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        if (verbose)
        {
            await stdout.WriteLineAsync($"[INFO] Applied git filter to {targetRelativePath}").ConfigureAwait(false);
        }

        return 0;
    }

    private async Task<int> ApplyImportOverridesAsync(
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
}
