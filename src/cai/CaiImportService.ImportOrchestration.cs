using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportService : CaiRuntimeSupport
{
    private async Task<int> RunImportCoreAsync(ParsedImportOptions options, CancellationToken cancellationToken)
    {
        var workspace = string.IsNullOrWhiteSpace(options.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(ExpandHomePath(options.Workspace));
        var explicitConfigPath = string.IsNullOrWhiteSpace(options.ConfigPath)
            ? null
            : Path.GetFullPath(ExpandHomePath(options.ConfigPath));

        if (!string.IsNullOrWhiteSpace(explicitConfigPath) && !File.Exists(explicitConfigPath))
        {
            await stderr.WriteLineAsync($"Config file not found: {explicitConfigPath}").ConfigureAwait(false);
            return 1;
        }

        var volume = await ResolveDataVolumeAsync(workspace, options.ExplicitVolume, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            await stderr.WriteLineAsync("Unable to resolve data volume. Use --data-volume.").ConfigureAwait(false);
            return 1;
        }

        var sourcePath = string.IsNullOrWhiteSpace(options.SourcePath)
            ? ResolveHomeDirectory()
            : Path.GetFullPath(ExpandHomePath(options.SourcePath));
        if (!File.Exists(sourcePath) && !Directory.Exists(sourcePath))
        {
            await stderr.WriteLineAsync($"Import source not found: {sourcePath}").ConfigureAwait(false);
            return 1;
        }

        var excludePriv = await ResolveImportExcludePrivAsync(workspace, explicitConfigPath, cancellationToken).ConfigureAwait(false);
        var context = ResolveDockerContextName();

        await stdout.WriteLineAsync($"Using data volume: {volume}").ConfigureAwait(false);
        if (options.DryRun)
        {
            await stdout.WriteLineAsync($"Dry-run context: {context}").ConfigureAwait(false);
        }

        if (!options.DryRun)
        {
            var ensureVolume = await DockerCaptureAsync(["volume", "create", volume], cancellationToken).ConfigureAwait(false);
            if (ensureVolume.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureVolume.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        ManifestEntry[] manifestEntries;
        try
        {
            var manifestDirectory = ResolveImportManifestDirectory();
            manifestEntries = ManifestTomlParser.Parse(manifestDirectory, includeDisabled: false, includeSourceFile: false)
                .Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal))
                .Where(static entry => !string.IsNullOrWhiteSpace(entry.Source))
                .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
                .ToArray();
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }

        if (File.Exists(sourcePath))
        {
            if (!sourcePath.EndsWith(".tgz", StringComparison.OrdinalIgnoreCase))
            {
                await stderr.WriteLineAsync($"Unsupported import source file type: {sourcePath}").ConfigureAwait(false);
                return 1;
            }

            if (!options.DryRun)
            {
                var restoreCode = await RestoreArchiveImportAsync(volume, sourcePath, excludePriv, cancellationToken).ConfigureAwait(false);
                if (restoreCode != 0)
                {
                    return restoreCode;
                }

                var applyOverrideCode = await ApplyImportOverridesAsync(
                    volume,
                    manifestEntries,
                    options.NoSecrets,
                    options.DryRun,
                    options.Verbose,
                    cancellationToken).ConfigureAwait(false);
                if (applyOverrideCode != 0)
                {
                    return applyOverrideCode;
                }
            }

            await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
            return 0;
        }

        var additionalImportPaths = await ResolveAdditionalImportPathsAsync(
            workspace,
            explicitConfigPath,
            excludePriv,
            sourcePath,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);

        if (!options.DryRun)
        {
            var initCode = await InitializeImportTargetsAsync(volume, sourcePath, manifestEntries, options.NoSecrets, cancellationToken).ConfigureAwait(false);
            if (initCode != 0)
            {
                return initCode;
            }
        }

        foreach (var entry in manifestEntries)
        {
            if (options.NoSecrets && entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                if (options.Verbose)
                {
                    await stderr.WriteLineAsync($"Skipping secret entry: {entry.Source}").ConfigureAwait(false);
                }

                continue;
            }

            var copyCode = await ImportManifestEntryAsync(
                volume,
                sourcePath,
                entry,
                excludePriv,
                options.NoExcludes,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        if (!options.DryRun)
        {
            var secretPermissionsCode = await EnforceSecretPathPermissionsAsync(
                volume,
                manifestEntries,
                options.NoSecrets,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (secretPermissionsCode != 0)
            {
                return secretPermissionsCode;
            }
        }

        foreach (var additionalPath in additionalImportPaths)
        {
            var copyCode = await ImportAdditionalPathAsync(
                volume,
                additionalPath,
                options.NoExcludes,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        var envCode = await ImportEnvironmentVariablesAsync(
            volume,
            workspace,
            explicitConfigPath,
            options.DryRun,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
        if (envCode != 0)
        {
            return envCode;
        }

        var overrideCode = await ApplyImportOverridesAsync(
            volume,
            manifestEntries,
            options.NoSecrets,
            options.DryRun,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
        if (overrideCode != 0)
        {
            return overrideCode;
        }

        await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var secretDirectories = new HashSet<string>(StringComparer.Ordinal);
        var secretFiles = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in manifestEntries)
        {
            if (!entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                continue;
            }

            if (noSecrets)
            {
                continue;
            }

            var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
            if (entry.Flags.Contains('d', StringComparison.Ordinal))
            {
                secretDirectories.Add(normalizedTarget);
            }
            else
            {
                secretFiles.Add(normalizedTarget);
                var parent = Path.GetDirectoryName(normalizedTarget)?.Replace("\\", "/", StringComparison.Ordinal);
                if (!string.IsNullOrWhiteSpace(parent))
                {
                    secretDirectories.Add(parent);
                }
            }
        }

        if (secretDirectories.Count == 0 && secretFiles.Count == 0)
        {
            return 0;
        }

        var commandBuilder = new StringBuilder();
        foreach (var directory in secretDirectories.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -d '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' ]; then chmod 700 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' || true; fi; ");
        }

        foreach (var file in secretFiles.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -f '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' ]; then chmod 600 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' || true; fi; ");
        }

        var result = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", commandBuilder.ToString()],
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(result.StandardError))
            {
                await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        if (verbose)
        {
            await stdout.WriteLineAsync("[INFO] Enforced secret path permissions").ConfigureAwait(false);
        }

        return 0;
    }

    private static async Task<bool> ResolveImportExcludePrivAsync(string workspace, string? explicitConfigPath, CancellationToken cancellationToken)
    {
        var configPath = !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : ResolveConfigPath(workspace);
        if (!File.Exists(configPath))
        {
            return true;
        }

        var result = await RunTomlAsync(() => TomlCommandProcessor.GetKey(configPath, "import.exclude_priv"), cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return true;
        }

        return !bool.TryParse(result.StandardOutput.Trim(), out var parsed) || parsed;
    }

    private async Task<IReadOnlyList<AdditionalImportPath>> ResolveAdditionalImportPathsAsync(
        string workspace,
        string? explicitConfigPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : ResolveConfigPath(workspace);
        if (!File.Exists(configPath))
        {
            return [];
        }

        var result = await RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (verbose && !string.IsNullOrWhiteSpace(result.StandardError))
            {
                await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(result.StandardOutput);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("import", out var importElement) ||
                importElement.ValueKind != JsonValueKind.Object ||
                !importElement.TryGetProperty("additional_paths", out var pathsElement))
            {
                return [];
            }

            if (pathsElement.ValueKind != JsonValueKind.Array)
            {
                await stderr.WriteLineAsync("[WARN] [import].additional_paths must be a list; ignoring").ConfigureAwait(false);
                return [];
            }

            var values = new List<AdditionalImportPath>();
            var seenSources = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in pathsElement.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.String)
                {
                    await stderr.WriteLineAsync($"[WARN] [import].additional_paths item must be a string; got {item.ValueKind}").ConfigureAwait(false);
                    continue;
                }

                var rawPath = item.GetString();
                if (!TryResolveAdditionalImportPath(rawPath, sourceRoot, excludePriv, out var resolved, out var warning))
                {
                    if (!string.IsNullOrWhiteSpace(warning))
                    {
                        await stderr.WriteLineAsync(warning).ConfigureAwait(false);
                    }

                    continue;
                }

                if (!seenSources.Add(resolved.SourcePath))
                {
                    continue;
                }

                values.Add(resolved);
            }

            return values;
        }
        catch (JsonException ex)
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"[WARN] Failed to parse config JSON for additional paths: {ex.Message}").ConfigureAwait(false);
            }

            return [];
        }
    }

    private static bool TryResolveAdditionalImportPath(
        string? rawPath,
        string sourceRoot,
        bool excludePriv,
        out AdditionalImportPath resolved,
        out string? warning)
    {
        resolved = default;
        warning = null;

        if (string.IsNullOrWhiteSpace(rawPath))
        {
            warning = "[WARN] [import].additional_paths entry is empty; skipping";
            return false;
        }

        if (rawPath.Contains(':', StringComparison.Ordinal))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' contains ':'; skipping";
            return false;
        }

        var effectiveHome = Path.GetFullPath(sourceRoot);
        var expandedPath = rawPath;
        if (rawPath.StartsWith('~'))
        {
            expandedPath = rawPath.Length == 1
                ? effectiveHome
                : rawPath[1] switch
                {
                    '/' or '\\' => Path.Combine(effectiveHome, rawPath[2..]),
                    _ => rawPath,
                };
        }
        if (rawPath.StartsWith('~') && !rawPath.StartsWith("~/", StringComparison.Ordinal) && !rawPath.StartsWith("~\\", StringComparison.Ordinal))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' uses unsupported user-home expansion; use ~/...";
            return false;
        }

        if (!Path.IsPathRooted(expandedPath))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' must be ~/... or absolute under HOME";
            return false;
        }

        var fullPath = Path.GetFullPath(expandedPath);
        if (!IsPathWithinDirectory(fullPath, effectiveHome))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' escapes HOME; skipping";
            return false;
        }

        if (!File.Exists(fullPath) && !Directory.Exists(fullPath))
        {
            return false;
        }

        if (ContainsSymlinkComponent(effectiveHome, fullPath))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' contains symlink components; skipping";
            return false;
        }

        var targetRelativePath = MapAdditionalPathTarget(effectiveHome, fullPath);
        if (string.IsNullOrWhiteSpace(targetRelativePath))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' resolved to an empty target; skipping";
            return false;
        }

        var isDirectory = Directory.Exists(fullPath);
        var applyPrivFilter = excludePriv && IsBashrcDirectoryPath(effectiveHome, fullPath);
        resolved = new AdditionalImportPath(fullPath, targetRelativePath, isDirectory, applyPrivFilter);
        return true;
    }

    private static bool IsPathWithinDirectory(string path, string directory)
    {
        var normalizedDirectory = Path.GetFullPath(directory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var normalizedPath = Path.GetFullPath(path)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (string.Equals(normalizedPath, normalizedDirectory, StringComparison.Ordinal))
        {
            return true;
        }

        return normalizedPath.StartsWith(
            normalizedDirectory + Path.DirectorySeparatorChar,
            StringComparison.Ordinal);
    }

    private static bool ContainsSymlinkComponent(string baseDirectory, string fullPath)
    {
        var relative = Path.GetRelativePath(baseDirectory, fullPath);
        if (relative.StartsWith("..", StringComparison.Ordinal))
        {
            return true;
        }

        var current = Path.GetFullPath(baseDirectory);
        var segments = relative.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);
        foreach (var segment in segments)
        {
            current = Path.Combine(current, segment);
            if (!File.Exists(current) && !Directory.Exists(current))
            {
                continue;
            }

            if (IsSymbolicLinkPath(current))
            {
                return true;
            }
        }

        return false;
    }

    private static string MapAdditionalPathTarget(string homeDirectory, string fullPath)
    {
        var relative = Path.GetRelativePath(homeDirectory, fullPath).Replace('\\', '/');
        if (string.Equals(relative, ".", StringComparison.Ordinal))
        {
            return string.Empty;
        }

        var segments = relative.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0)
        {
            return string.Empty;
        }

        var first = segments[0];
        if (first.StartsWith('.'))
        {
            first = first.TrimStart('.');
        }

        if (string.IsNullOrWhiteSpace(first))
        {
            return string.Empty;
        }

        segments[0] = first;
        return string.Join('/', segments);
    }

    private static bool IsBashrcDirectoryPath(string homeDirectory, string fullPath)
    {
        var normalized = Path.GetFullPath(fullPath);
        var bashrcDir = Path.Combine(Path.GetFullPath(homeDirectory), ".bashrc.d");
        return IsPathWithinDirectory(normalized, bashrcDir);
    }

    private async Task<int> ImportAdditionalPathAsync(
        string volume,
        AdditionalImportPath additionalPath,
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
                normalizedError += $"{Environment.NewLine}cannot delete non-empty directory";
            }

            await stderr.WriteLineAsync(normalizedError).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private static string ResolveDockerContextName()
    {
        var explicitContext = Environment.GetEnvironmentVariable("DOCKER_CONTEXT");
        if (!string.IsNullOrWhiteSpace(explicitContext))
        {
            return explicitContext;
        }

        return "default";
    }

    private static string ResolveRsyncImage()
    {
        var configured = Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }

    private static string ResolveImportManifestDirectory()
    {
        var candidates = ResolveManifestDirectoryCandidates();
        foreach (var candidate in candidates)
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException($"manifest directory not found; tried: {string.Join(", ", candidates)}");
    }

    private static string[] ResolveManifestDirectoryCandidates()
    {
        var candidates = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        static void AddCandidate(ICollection<string> target, ISet<string> seenSet, string? path)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                return;
            }

            var fullPath = Path.GetFullPath(path);
            if (seenSet.Add(fullPath))
            {
                target.Add(fullPath);
            }
        }

        var installRoot = InstallMetadata.ResolveInstallDirectory();
        AddCandidate(candidates, seen, Path.Combine(installRoot, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(installRoot, "src", "manifests"));

        var appBase = Path.GetFullPath(AppContext.BaseDirectory);
        AddCandidate(candidates, seen, Path.Combine(appBase, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "..", "manifests"));

        var current = Directory.GetCurrentDirectory();
        AddCandidate(candidates, seen, Path.Combine(current, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(current, "src", "manifests"));

        AddCandidate(candidates, seen, "/opt/containai/manifests");
        return candidates.ToArray();
    }

}
