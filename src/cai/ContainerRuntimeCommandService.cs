using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed class ContainerRuntimeCommandService
{
    private const string DefaultDataDir = "/mnt/agent-data";
    private const string DefaultHomeDir = "/home/agent";
    private const string DefaultWorkspaceDir = "/home/agent/workspace";
    private const string DefaultBuiltinManifestsDir = "/opt/containai/manifests";
    private const string DefaultTemplateHooksDir = "/etc/containai/template-hooks/startup.d";
    private const string DefaultWorkspaceHooksDir = "/home/agent/workspace/.containai/hooks/startup.d";
    private const string DefaultBuiltinLinkSpec = "/usr/local/lib/containai/link-spec.json";
    private const string DefaultUserLinkSpec = "/mnt/agent-data/containai/user-link-spec.json";
    private const string DefaultImportedAtFile = "/mnt/agent-data/.containai-imported-at";
    private const string DefaultCheckedAtFile = "/mnt/agent-data/.containai-links-checked-at";

    private readonly TextWriter _stdout;
    private readonly TextWriter _stderr;

    public ContainerRuntimeCommandService(TextWriter stdout, TextWriter stderr)
    {
        _stdout = stdout;
        _stderr = stderr;
    }

    public async Task<int> RunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2)
        {
            await _stderr.WriteLineAsync("Usage: cai system <init|link-repair|watch-links|devcontainer>").ConfigureAwait(false);
            return 1;
        }

        return args[1] switch
        {
            "init" => await RunInitAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false),
            "link-repair" => await RunLinkRepairAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false),
            "watch-links" => await RunLinkWatcherAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false),
            "devcontainer" => await new DevcontainerFeatureRuntime(_stdout, _stderr).RunAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false),
            _ => await UnknownSystemSubcommandAsync(args[1]).ConfigureAwait(false),
        };
    }

    private async Task<int> UnknownSystemSubcommandAsync(string subcommand)
    {
        await _stderr.WriteLineAsync($"Unknown system subcommand: {subcommand}").ConfigureAwait(false);
        await _stderr.WriteLineAsync("Usage: cai system <init|link-repair|watch-links|devcontainer>").ConfigureAwait(false);
        return 1;
    }

    private async Task<int> RunInitAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var quiet = false;
        var dataDir = DefaultDataDir;
        var homeDir = DefaultHomeDir;
        var manifestsDir = DefaultBuiltinManifestsDir;
        var templateHooksDir = DefaultTemplateHooksDir;
        var workspaceHooksDir = DefaultWorkspaceHooksDir;
        var workspaceDir = DefaultWorkspaceDir;
        for (var index = 0; index < args.Count; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--help":
                case "-h":
                    await _stdout.WriteLineAsync(
                        "Usage: cai system init [--data-dir <path>] [--home-dir <path>] [--manifests-dir <path>] [--template-hooks <path>] [--workspace-hooks <path>] [--workspace-dir <path>] [--quiet]").ConfigureAwait(false);
                    return 0;
                case "--quiet":
                    quiet = true;
                    break;
                case "--data-dir":
                    if (!TryReadOptionValue(args, ref index, out dataDir))
                    {
                        await _stderr.WriteLineAsync("--data-dir requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--home-dir":
                    if (!TryReadOptionValue(args, ref index, out homeDir))
                    {
                        await _stderr.WriteLineAsync("--home-dir requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--manifests-dir":
                    if (!TryReadOptionValue(args, ref index, out manifestsDir))
                    {
                        await _stderr.WriteLineAsync("--manifests-dir requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--template-hooks":
                    if (!TryReadOptionValue(args, ref index, out templateHooksDir))
                    {
                        await _stderr.WriteLineAsync("--template-hooks requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--workspace-hooks":
                    if (!TryReadOptionValue(args, ref index, out workspaceHooksDir))
                    {
                        await _stderr.WriteLineAsync("--workspace-hooks requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--workspace-dir":
                    if (!TryReadOptionValue(args, ref index, out workspaceDir))
                    {
                        await _stderr.WriteLineAsync("--workspace-dir requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                default:
                    await _stderr.WriteLineAsync($"Unknown system init option: {token}").ConfigureAwait(false);
                    return 1;
            }
        }

        try
        {
            await LogInfoAsync(quiet, "ContainAI initialization starting...").ConfigureAwait(false);

            await UpdateAgentPasswordAsync().ConfigureAwait(false);
            await EnsureVolumeStructureAsync(dataDir, manifestsDir, quiet).ConfigureAwait(false);
            await LoadEnvFileAsync(Path.Combine(dataDir, ".env"), quiet).ConfigureAwait(false);
            await MigrateGitConfigAsync(dataDir, quiet).ConfigureAwait(false);
            await SetupGitConfigAsync(dataDir, homeDir, quiet).ConfigureAwait(false);
            await SetupWorkspaceSymlinkAsync(workspaceDir, quiet).ConfigureAwait(false);
            await ProcessUserManifestsAsync(dataDir, homeDir, quiet).ConfigureAwait(false);

            await RunHooksAsync(templateHooksDir, workspaceDir, homeDir, quiet, cancellationToken).ConfigureAwait(false);
            await RunHooksAsync(workspaceHooksDir, workspaceDir, homeDir, quiet, cancellationToken).ConfigureAwait(false);

            await LogInfoAsync(quiet, "ContainAI initialization complete").ConfigureAwait(false);
            return 0;
        }
        catch (Exception ex)
        {
            await _stderr.WriteLineAsync($"[ERROR] {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunLinkRepairAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var mode = LinkRepairMode.Check;
        var quiet = false;
        var builtinSpecPath = DefaultBuiltinLinkSpec;
        var userSpecPath = DefaultUserLinkSpec;
        var checkedAtFilePath = DefaultCheckedAtFile;
        for (var index = 0; index < args.Count; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--help":
                case "-h":
                    await _stdout.WriteLineAsync(
                        "Usage: cai system link-repair [--check|--fix|--dry-run] [--quiet] [--builtin-spec <path>] [--user-spec <path>] [--checked-at-file <path>]").ConfigureAwait(false);
                    return 0;
                case "--check":
                    mode = LinkRepairMode.Check;
                    break;
                case "--fix":
                    mode = LinkRepairMode.Fix;
                    break;
                case "--dry-run":
                    mode = LinkRepairMode.DryRun;
                    break;
                case "--quiet":
                    quiet = true;
                    break;
                case "--builtin-spec":
                    if (!TryReadOptionValue(args, ref index, out builtinSpecPath))
                    {
                        await _stderr.WriteLineAsync("--builtin-spec requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--user-spec":
                    if (!TryReadOptionValue(args, ref index, out userSpecPath))
                    {
                        await _stderr.WriteLineAsync("--user-spec requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--checked-at-file":
                    if (!TryReadOptionValue(args, ref index, out checkedAtFilePath))
                    {
                        await _stderr.WriteLineAsync("--checked-at-file requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                default:
                    await _stderr.WriteLineAsync($"Unknown system link-repair option: {token}").ConfigureAwait(false);
                    return 1;
            }
        }

        if (!File.Exists(builtinSpecPath))
        {
            await _stderr.WriteLineAsync($"ERROR: Built-in link spec not found: {builtinSpecPath}").ConfigureAwait(false);
            return 1;
        }

        var stats = new LinkRepairStats();
        try
        {
            await ProcessLinkSpecAsync(builtinSpecPath, mode, quiet, "built-in links", stats, cancellationToken).ConfigureAwait(false);
            if (File.Exists(userSpecPath))
            {
                try
                {
                    await ProcessLinkSpecAsync(userSpecPath, mode, quiet, "user-defined links", stats, cancellationToken).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    stats.Errors++;
                    await _stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {ex.Message}").ConfigureAwait(false);
                }
            }

            if (mode == LinkRepairMode.Fix && stats.Errors == 0)
            {
                await WriteTimestampAsync(checkedAtFilePath).ConfigureAwait(false);
                await LogInfoAsync(quiet, "Updated links-checked-at timestamp").ConfigureAwait(false);
            }

            await WriteLinkRepairSummaryAsync(mode, stats, quiet).ConfigureAwait(false);
            if (stats.Errors > 0)
            {
                return 1;
            }

            if (mode == LinkRepairMode.Check && (stats.Broken + stats.Missing) > 0)
            {
                return 1;
            }

            return 0;
        }
        catch (Exception ex)
        {
            await _stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunLinkWatcherAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var pollIntervalSeconds = 60;
        var importedAtPath = DefaultImportedAtFile;
        var checkedAtPath = DefaultCheckedAtFile;
        var quiet = false;
        for (var index = 0; index < args.Count; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--help":
                case "-h":
                    await _stdout.WriteLineAsync("Usage: cai system watch-links [--poll-interval <seconds>] [--imported-at-file <path>] [--checked-at-file <path>] [--quiet]").ConfigureAwait(false);
                    return 0;
                case "--quiet":
                    quiet = true;
                    break;
                case "--poll-interval":
                    if (!TryReadOptionValue(args, ref index, out var intervalRaw) || !int.TryParse(intervalRaw, out pollIntervalSeconds) || pollIntervalSeconds < 1)
                    {
                        await _stderr.WriteLineAsync("--poll-interval requires a positive integer value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--imported-at-file":
                    if (!TryReadOptionValue(args, ref index, out importedAtPath))
                    {
                        await _stderr.WriteLineAsync("--imported-at-file requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                case "--checked-at-file":
                    if (!TryReadOptionValue(args, ref index, out checkedAtPath))
                    {
                        await _stderr.WriteLineAsync("--checked-at-file requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                default:
                    await _stderr.WriteLineAsync($"Unknown system watch-links option: {token}").ConfigureAwait(false);
                    return 1;
            }
        }

        await LogInfoAsync(quiet, $"Link watcher started (poll interval: {pollIntervalSeconds}s)").ConfigureAwait(false);
        await LogInfoAsync(quiet, $"Watching: {importedAtPath} vs {checkedAtPath}").ConfigureAwait(false);

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(pollIntervalSeconds), cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            if (!File.Exists(importedAtPath))
            {
                continue;
            }

            var importedTimestamp = await TryReadTrimmedTextAsync(importedAtPath).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(importedTimestamp))
            {
                continue;
            }

            var checkedTimestamp = await TryReadTrimmedTextAsync(checkedAtPath).ConfigureAwait(false) ?? string.Empty;
            if (!string.IsNullOrEmpty(checkedTimestamp) && string.CompareOrdinal(importedTimestamp, checkedTimestamp) <= 0)
            {
                continue;
            }

            await LogInfoAsync(quiet, $"Import newer than last check (imported={importedTimestamp}, checked={(string.IsNullOrWhiteSpace(checkedTimestamp) ? "never" : checkedTimestamp)}), running repair...").ConfigureAwait(false);
            var exitCode = await RunLinkRepairAsync(
                ["--fix", "--quiet", "--checked-at-file", checkedAtPath],
                cancellationToken).ConfigureAwait(false);
            if (exitCode == 0)
            {
                await LogInfoAsync(quiet, "Repair completed successfully").ConfigureAwait(false);
            }
            else
            {
                await _stderr.WriteLineAsync("[ERROR] Repair command failed").ConfigureAwait(false);
            }
        }

        return 0;
    }

    private async Task ProcessLinkSpecAsync(
        string specPath,
        LinkRepairMode mode,
        bool quiet,
        string specName,
        LinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var json = await File.ReadAllTextAsync(specPath, cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("links", out var linksElement) || linksElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException($"Invalid link spec format: {specPath}");
        }

        await LogInfoAsync(quiet, $"Processing {specName} ({linksElement.GetArrayLength()} links)").ConfigureAwait(false);

        foreach (var linkElement in linksElement.EnumerateArray())
        {
            cancellationToken.ThrowIfCancellationRequested();
            var linkPath = linkElement.TryGetProperty("link", out var linkValue) ? linkValue.GetString() : null;
            var targetPath = linkElement.TryGetProperty("target", out var targetValue) ? targetValue.GetString() : null;
            var removeFirst = linkElement.TryGetProperty("remove_first", out var removeFirstValue) && removeFirstValue.ValueKind == JsonValueKind.True;
            if (string.IsNullOrWhiteSpace(linkPath) || string.IsNullOrWhiteSpace(targetPath))
            {
                stats.Errors++;
                await _stderr.WriteLineAsync($"[WARN] Skipping invalid link spec entry in {specPath}").ConfigureAwait(false);
                continue;
            }

            await ProcessLinkEntryAsync(linkPath!, targetPath!, removeFirst, mode, quiet, stats).ConfigureAwait(false);
        }
    }

    private async Task ProcessLinkEntryAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats)
    {
        var isSymlink = await IsSymlinkAsync(linkPath).ConfigureAwait(false);
        if (isSymlink)
        {
            var currentTarget = await ReadLinkTargetAsync(linkPath).ConfigureAwait(false);
            if (string.Equals(currentTarget, targetPath, StringComparison.Ordinal))
            {
                if (!File.Exists(linkPath) && !Directory.Exists(linkPath))
                {
                    stats.Broken++;
                    await LogInfoAsync(quiet, $"[BROKEN] {linkPath} -> {targetPath} (dangling symlink)").ConfigureAwait(false);
                }
                else
                {
                    stats.Ok++;
                    return;
                }
            }
            else
            {
                stats.Broken++;
                await LogInfoAsync(quiet, $"[WRONG_TARGET] {linkPath} -> {currentTarget} (expected: {targetPath})").ConfigureAwait(false);
            }
        }
        else if (Directory.Exists(linkPath))
        {
            if (removeFirst)
            {
                stats.Broken++;
                await LogInfoAsync(quiet, $"[EXISTS_DIR] {linkPath} is a directory (will remove with R flag)").ConfigureAwait(false);
            }
            else
            {
                stats.Errors++;
                await _stderr.WriteLineAsync($"[CONFLICT] {linkPath} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
                return;
            }
        }
        else if (File.Exists(linkPath))
        {
            stats.Broken++;
            await LogInfoAsync(quiet, $"[EXISTS_FILE] {linkPath} is a regular file (will replace)").ConfigureAwait(false);
        }
        else
        {
            stats.Missing++;
            await LogInfoAsync(quiet, $"[MISSING] {linkPath} -> {targetPath}").ConfigureAwait(false);
        }

        if (mode == LinkRepairMode.Check)
        {
            return;
        }

        var parent = Path.GetDirectoryName(linkPath);
        if (!string.IsNullOrWhiteSpace(parent) && !Directory.Exists(parent))
        {
            if (mode == LinkRepairMode.DryRun)
            {
                await LogInfoAsync(quiet, $"[WOULD] Create parent directory: {parent}").ConfigureAwait(false);
            }
            else
            {
                Directory.CreateDirectory(parent);
            }
        }

        if (Directory.Exists(linkPath) && !await IsSymlinkAsync(linkPath).ConfigureAwait(false))
        {
            if (!removeFirst)
            {
                stats.Errors++;
                await _stderr.WriteLineAsync($"ERROR: Cannot fix - directory exists without R flag: {linkPath}").ConfigureAwait(false);
                return;
            }

            if (mode == LinkRepairMode.DryRun)
            {
                await LogInfoAsync(quiet, $"[WOULD] Remove directory: {linkPath}").ConfigureAwait(false);
            }
            else
            {
                Directory.Delete(linkPath, recursive: true);
            }
        }
        else if (File.Exists(linkPath) || await IsSymlinkAsync(linkPath).ConfigureAwait(false))
        {
            if (mode == LinkRepairMode.DryRun)
            {
                await LogInfoAsync(quiet, $"[WOULD] Replace path: {linkPath}").ConfigureAwait(false);
            }
            else
            {
                File.Delete(linkPath);
            }
        }

        if (mode == LinkRepairMode.DryRun)
        {
            await LogInfoAsync(quiet, $"[WOULD] Create symlink: {linkPath} -> {targetPath}").ConfigureAwait(false);
            stats.Fixed++;
            return;
        }

        File.CreateSymbolicLink(linkPath, targetPath);
        await LogInfoAsync(quiet, $"[FIXED] {linkPath} -> {targetPath}").ConfigureAwait(false);
        stats.Fixed++;
    }

    private async Task WriteLinkRepairSummaryAsync(LinkRepairMode mode, LinkRepairStats stats, bool quiet)
    {
        if (quiet)
        {
            return;
        }

        await _stdout.WriteLineAsync().ConfigureAwait(false);
        await _stdout.WriteLineAsync(mode == LinkRepairMode.DryRun ? "=== Dry-Run Summary ===" : "=== Link Status Summary ===").ConfigureAwait(false);
        await _stdout.WriteLineAsync($"  OK:      {stats.Ok}").ConfigureAwait(false);
        await _stdout.WriteLineAsync($"  Broken:  {stats.Broken}").ConfigureAwait(false);
        await _stdout.WriteLineAsync($"  Missing: {stats.Missing}").ConfigureAwait(false);
        if (mode == LinkRepairMode.Fix)
        {
            await _stdout.WriteLineAsync($"  Fixed:   {stats.Fixed}").ConfigureAwait(false);
        }
        else if (mode == LinkRepairMode.DryRun)
        {
            await _stdout.WriteLineAsync($"  Would fix: {stats.Fixed}").ConfigureAwait(false);
        }

        await _stdout.WriteLineAsync($"  Errors:  {stats.Errors}").ConfigureAwait(false);
    }

    private async Task EnsureVolumeStructureAsync(string dataDir, string manifestsDir, bool quiet)
    {
        await RunAsRootAsync("mkdir", ["-p", dataDir]).ConfigureAwait(false);
        await RunAsRootAsync("chown", ["-R", "--no-dereference", "1000:1000", dataDir]).ConfigureAwait(false);

        if (Directory.Exists(manifestsDir))
        {
            await LogInfoAsync(quiet, "Applying init directory policy from manifests").ConfigureAwait(false);
            try
            {
                _ = ManifestApplier.ApplyInitDirs(manifestsDir, dataDir);
            }
            catch (Exception ex)
            {
                await _stderr.WriteLineAsync($"[WARN] Native init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
        }
        else
        {
            await _stderr.WriteLineAsync("[WARN] Built-in manifests not found, using fallback volume structure").ConfigureAwait(false);
            EnsureFallbackVolumeStructure(dataDir);
        }

        await RunAsRootAsync("chown", ["-R", "--no-dereference", "1000:1000", dataDir]).ConfigureAwait(false);
    }

    private static void EnsureFallbackVolumeStructure(string dataDir)
    {
        Directory.CreateDirectory(Path.Combine(dataDir, "claude"));
        Directory.CreateDirectory(Path.Combine(dataDir, "config", "gh"));
        Directory.CreateDirectory(Path.Combine(dataDir, "git"));
        EnsureFileWithContent(Path.Combine(dataDir, "git", "gitconfig"), null);
        EnsureFileWithContent(Path.Combine(dataDir, "git", "gitignore_global"), null);
        Directory.CreateDirectory(Path.Combine(dataDir, "shell"));
        Directory.CreateDirectory(Path.Combine(dataDir, "editors"));
        Directory.CreateDirectory(Path.Combine(dataDir, "config"));
    }

    private async Task LoadEnvFileAsync(string envFilePath, bool quiet)
    {
        if (await IsSymlinkAsync(envFilePath).ConfigureAwait(false))
        {
            await _stderr.WriteLineAsync("[WARN] .env is symlink - skipping").ConfigureAwait(false);
            return;
        }

        if (!File.Exists(envFilePath))
        {
            return;
        }

        try
        {
            _ = File.OpenRead(envFilePath);
        }
        catch
        {
            await _stderr.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
            return;
        }

        await LogInfoAsync(quiet, "Loading environment from .env").ConfigureAwait(false);

        var lines = await File.ReadAllLinesAsync(envFilePath).ConfigureAwait(false);
        for (var index = 0; index < lines.Length; index++)
        {
            var line = lines[index].TrimEnd('\r');
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            if (line.TrimStart().StartsWith("#", StringComparison.Ordinal))
            {
                continue;
            }

            if (line.StartsWith("export ", StringComparison.Ordinal))
            {
                line = line[7..].TrimStart();
            }

            var separator = line.IndexOf('=', StringComparison.Ordinal);
            if (separator <= 0)
            {
                continue;
            }

            var key = line[..separator];
            var value = line[(separator + 1)..];
            if (!IsValidEnvKey(key))
            {
                await _stderr.WriteLineAsync($"[WARN] line {index + 1}: invalid key '{key}' - skipping").ConfigureAwait(false);
                continue;
            }

            if (Environment.GetEnvironmentVariable(key) is null)
            {
                Environment.SetEnvironmentVariable(key, value);
            }
        }
    }

    private static bool IsValidEnvKey(string key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return false;
        }

        if (!(char.IsLetter(key[0]) || key[0] == '_'))
        {
            return false;
        }

        for (var index = 1; index < key.Length; index++)
        {
            var c = key[index];
            if (!(char.IsLetterOrDigit(c) || c == '_'))
            {
                return false;
            }
        }

        return true;
    }

    private async Task MigrateGitConfigAsync(string dataDir, bool quiet)
    {
        var oldPath = Path.Combine(dataDir, ".gitconfig");
        var newDir = Path.Combine(dataDir, "git");
        var newPath = Path.Combine(newDir, "gitconfig");

        if (!File.Exists(oldPath) || await IsSymlinkAsync(oldPath).ConfigureAwait(false))
        {
            return;
        }

        var oldInfo = new FileInfo(oldPath);
        if (oldInfo.Length == 0)
        {
            return;
        }

        var needsNewPath = !File.Exists(newPath) || new FileInfo(newPath).Length == 0;
        if (!needsNewPath)
        {
            return;
        }

        if (await IsSymlinkAsync(newDir).ConfigureAwait(false))
        {
            await _stderr.WriteLineAsync($"[WARN] {newDir} is a symlink - cannot migrate git config").ConfigureAwait(false);
            return;
        }

        Directory.CreateDirectory(newDir);
        if (await IsSymlinkAsync(newPath).ConfigureAwait(false))
        {
            await _stderr.WriteLineAsync($"[WARN] {newPath} is a symlink - cannot migrate git config").ConfigureAwait(false);
            return;
        }

        var tempPath = $"{newPath}.tmp.{Environment.ProcessId}";
        File.Copy(oldPath, tempPath, overwrite: true);
        File.Move(tempPath, newPath, overwrite: true);
        File.Delete(oldPath);
        await LogInfoAsync(quiet, $"Migrated git config from {oldPath} to {newPath}").ConfigureAwait(false);
    }

    private async Task SetupGitConfigAsync(string dataDir, string homeDir, bool quiet)
    {
        var destination = Path.Combine(homeDir, ".gitconfig");
        if (await IsSymlinkAsync(destination).ConfigureAwait(false))
        {
            return;
        }

        var primarySource = Path.Combine(dataDir, "git", "gitconfig");
        var legacySource = Path.Combine(dataDir, ".gitconfig");
        var source = ChooseReadableNonEmptyFile(primarySource, legacySource);
        if (source is null)
        {
            return;
        }

        if (Directory.Exists(destination))
        {
            await _stderr.WriteLineAsync($"[WARN] Destination {destination} exists but is not a regular file - skipping").ConfigureAwait(false);
            return;
        }

        var tempDestination = $"{destination}.tmp.{Environment.ProcessId}";
        File.Copy(source, tempDestination, overwrite: true);
        File.Move(tempDestination, destination, overwrite: true);
        await LogInfoAsync(quiet, "Git config loaded from data volume").ConfigureAwait(false);
    }

    private static string? ChooseReadableNonEmptyFile(params string[] paths)
    {
        foreach (var path in paths)
        {
            if (!File.Exists(path))
            {
                continue;
            }

            var info = new FileInfo(path);
            if (info.Length == 0)
            {
                continue;
            }

            return path;
        }

        return null;
    }

    private async Task SetupWorkspaceSymlinkAsync(string workspaceDir, bool quiet)
    {
        var hostWorkspace = Environment.GetEnvironmentVariable("CAI_HOST_WORKSPACE");
        if (string.IsNullOrWhiteSpace(hostWorkspace))
        {
            return;
        }

        if (string.Equals(hostWorkspace, workspaceDir, StringComparison.Ordinal))
        {
            return;
        }

        if (!Path.IsPathRooted(hostWorkspace))
        {
            await _stderr.WriteLineAsync($"[WARN] CAI_HOST_WORKSPACE must be absolute path: {hostWorkspace}").ConfigureAwait(false);
            return;
        }

        if (!IsAllowedWorkspacePrefix(hostWorkspace))
        {
            await _stderr.WriteLineAsync($"[WARN] CAI_HOST_WORKSPACE must be under /home/, /tmp/, /mnt/, /workspaces/, or /Users/: {hostWorkspace}").ConfigureAwait(false);
            return;
        }

        var parent = Path.GetDirectoryName(hostWorkspace);
        if (string.IsNullOrWhiteSpace(parent))
        {
            return;
        }

        await RunAsRootAsync("mkdir", ["-p", parent]).ConfigureAwait(false);
        await RunAsRootAsync("ln", ["-sfn", workspaceDir, hostWorkspace]).ConfigureAwait(false);
        await LogInfoAsync(quiet, $"Workspace symlink created: {hostWorkspace} -> {workspaceDir}").ConfigureAwait(false);
    }

    private static bool IsAllowedWorkspacePrefix(string path) => path.StartsWith("/home/", StringComparison.Ordinal) ||
               path.StartsWith("/tmp/", StringComparison.Ordinal) ||
               path.StartsWith("/mnt/", StringComparison.Ordinal) ||
               path.StartsWith("/workspaces/", StringComparison.Ordinal) ||
               path.StartsWith("/Users/", StringComparison.Ordinal);

    private async Task ProcessUserManifestsAsync(string dataDir, string homeDir, bool quiet)
    {
        var userManifestDirectory = Path.Combine(dataDir, "containai", "manifests");
        if (!Directory.Exists(userManifestDirectory))
        {
            return;
        }

        var manifestFiles = Directory.EnumerateFiles(userManifestDirectory, "*.toml", SearchOption.TopDirectoryOnly).ToArray();
        if (manifestFiles.Length == 0)
        {
            return;
        }

        await LogInfoAsync(quiet, $"Found {manifestFiles.Length} user manifest(s), generating runtime configuration...").ConfigureAwait(false);
        try
        {
            _ = ManifestApplier.ApplyInitDirs(userManifestDirectory, dataDir);
            _ = ManifestApplier.ApplyContainerLinks(userManifestDirectory, homeDir, dataDir);

            var userSpec = ManifestGenerators.GenerateContainerLinkSpec(userManifestDirectory);
            var userSpecPath = Path.Combine(dataDir, "containai", "user-link-spec.json");
            Directory.CreateDirectory(Path.GetDirectoryName(userSpecPath)!);
            await File.WriteAllTextAsync(userSpecPath, userSpec.Content).ConfigureAwait(false);

            var userWrappers = ManifestGenerators.GenerateAgentWrappers(userManifestDirectory);
            var bashEnvDirectory = Path.Combine(homeDir, ".bash_env.d");
            Directory.CreateDirectory(bashEnvDirectory);
            var userWrapperPath = Path.Combine(bashEnvDirectory, "containai-user-agents.sh");
            await File.WriteAllTextAsync(userWrapperPath, userWrappers.Content).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            await _stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
    }

    private async Task RunHooksAsync(
        string hooksDirectory,
        string workspaceDirectory,
        string homeDirectory,
        bool quiet,
        CancellationToken cancellationToken)
    {
        if (!Directory.Exists(hooksDirectory))
        {
            return;
        }

        var hooks = Directory.EnumerateFiles(hooksDirectory, "*.sh", SearchOption.TopDirectoryOnly)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
        if (hooks.Length == 0)
        {
            return;
        }

        var workingDirectory = Directory.Exists(workspaceDirectory) ? workspaceDirectory : homeDirectory;
        foreach (var hook in hooks)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!IsExecutable(hook))
            {
                await _stderr.WriteLineAsync($"[WARN] Skipping non-executable hook: {hook}").ConfigureAwait(false);
                continue;
            }

            await LogInfoAsync(quiet, $"Running startup hook: {hook}").ConfigureAwait(false);
            var result = await RunProcessCaptureAsync(
                hook,
                [],
                workingDirectory,
                cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException($"Startup hook failed: {hook}: {result.StandardError.Trim()}");
            }
        }

        await LogInfoAsync(quiet, $"Completed hooks from: {hooksDirectory}").ConfigureAwait(false);
    }

    private async Task UpdateAgentPasswordAsync()
    {
        const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        Span<byte> randomBytes = stackalloc byte[32];
        RandomNumberGenerator.Fill(randomBytes);
        var builder = new StringBuilder(capacity: randomBytes.Length);
        foreach (var b in randomBytes)
        {
            builder.Append(alphabet[b % alphabet.Length]);
        }

        var payload = $"agent:{builder}\n";
        _ = await RunAsRootCaptureAsync("chpasswd", [], payload, CancellationToken.None).ConfigureAwait(false);
    }

    private static bool IsExecutable(string path)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                var extension = Path.GetExtension(path);
                return extension.Equals(".exe", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".bat", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".com", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase);
            }

            var mode = File.GetUnixFileMode(path);
            return (mode & (UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute)) != 0;
        }
        catch
        {
            return false;
        }
    }

    private async Task<bool> IsSymlinkAsync(string path)
    {
        var result = await RunProcessCaptureAsync("test", ["-L", path], null, CancellationToken.None).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private async Task<string?> ReadLinkTargetAsync(string path)
    {
        var result = await RunProcessCaptureAsync("readlink", [path], null, CancellationToken.None).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return null;
        }

        return result.StandardOutput.Trim();
    }

    private async Task<string?> TryReadTrimmedTextAsync(string path)
    {
        try
        {
            return (await File.ReadAllTextAsync(path).ConfigureAwait(false)).Trim();
        }
        catch
        {
            return null;
        }
    }

    private static void EnsureFileWithContent(string path, string? content)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        if (!File.Exists(path))
        {
            using (File.Create(path))
            {
            }
        }

        if (content is not null && new FileInfo(path).Length == 0)
        {
            File.WriteAllText(path, content);
        }
    }

    private async Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments) => _ = await RunAsRootCaptureAsync(executable, arguments, null, CancellationToken.None).ConfigureAwait(false);

    private async Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        if (IsRunningAsRoot())
        {
            var direct = await RunProcessCaptureAsync(executable, arguments, null, cancellationToken, standardInput).ConfigureAwait(false);
            if (direct.ExitCode != 0)
            {
                throw new InvalidOperationException($"Command failed: {executable} {string.Join(' ', arguments)}: {direct.StandardError.Trim()}");
            }

            return direct;
        }

        var sudoArguments = new List<string>(capacity: arguments.Count + 2)
        {
            "-n",
            executable,
        };
        foreach (var argument in arguments)
        {
            sudoArguments.Add(argument);
        }

        var sudo = await RunProcessCaptureAsync("sudo", sudoArguments, null, cancellationToken, standardInput).ConfigureAwait(false);
        if (sudo.ExitCode != 0)
        {
            throw new InvalidOperationException($"sudo command failed for {executable}: {sudo.StandardError.Trim()}");
        }

        return sudo;
    }

    private static bool IsRunningAsRoot()
    {
        try
        {
            return string.Equals(Environment.UserName, "root", StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

    private async Task LogInfoAsync(bool quiet, string message)
    {
        if (quiet)
        {
            return;
        }

        await _stdout.WriteLineAsync($"[INFO] {message}").ConfigureAwait(false);
    }

    private static bool TryReadOptionValue(IReadOnlyList<string> args, ref int index, out string value)
    {
        value = string.Empty;
        if (index + 1 >= args.Count)
        {
            return false;
        }

        index++;
        value = args[index];
        return true;
    }

    private static async Task WriteTimestampAsync(string path)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var temporaryPath = $"{path}.tmp.{Environment.ProcessId}";
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", System.Globalization.CultureInfo.InvariantCulture) + Environment.NewLine;
        await File.WriteAllTextAsync(temporaryPath, timestamp).ConfigureAwait(false);
        File.Move(temporaryPath, path, overwrite: true);
    }

    private static async Task<ProcessCaptureResult> RunProcessCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo(executable)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = standardInput is not null,
                UseShellExecute = false,
            },
        };

        if (!string.IsNullOrWhiteSpace(workingDirectory))
        {
            process.StartInfo.WorkingDirectory = workingDirectory;
        }

        foreach (var argument in arguments)
        {
            process.StartInfo.ArgumentList.Add(argument);
        }

        process.Start();
        if (standardInput is not null)
        {
            await process.StandardInput.WriteAsync(standardInput).ConfigureAwait(false);
            await process.StandardInput.FlushAsync().ConfigureAwait(false);
            process.StandardInput.Close();
        }

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

        return new ProcessCaptureResult(
            process.ExitCode,
            await stdoutTask.ConfigureAwait(false),
            await stderrTask.ConfigureAwait(false));
    }

    private sealed class LinkRepairStats
    {
        public int Broken { get; set; }

        public int Missing { get; set; }

        public int Ok { get; set; }

        public int Fixed { get; set; }

        public int Errors { get; set; }
    }

    private enum LinkRepairMode
    {
        Check,
        Fix,
        DryRun,
    }

    private sealed record ProcessCaptureResult(int ExitCode, string StandardOutput, string StandardError);
}
