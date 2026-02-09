using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ContainAI.Cli.Abstractions;

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

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly DevcontainerFeatureRuntime devcontainerRuntime;

    public ContainerRuntimeCommandService(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
        devcontainerRuntime = new DevcontainerFeatureRuntime(stdout, stderr);
    }

    public Task<int> RunSystemAsync(CancellationToken cancellationToken)
        => WriteSystemUsageAndFailAsync();

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunInitCoreAsync(options, cancellationToken);
    }

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunLinkRepairCoreAsync(options, cancellationToken);
    }

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunLinkWatcherCoreAsync(options, cancellationToken);
    }

    public Task<int> RunSystemDevcontainerAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunDevcontainerAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return devcontainerRuntime.RunInstallAsync(options, cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunInitAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunStartAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunVerifySysboxAsync(cancellationToken);

    private async Task<int> WriteSystemUsageAndFailAsync()
    {
        await stderr.WriteLineAsync("Usage: cai system <init|link-repair|watch-links|devcontainer>").ConfigureAwait(false);
        return 1;
    }

    private async Task<int> RunInitCoreAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        var quiet = options.Quiet;
        var dataDir = string.IsNullOrWhiteSpace(options.DataDir) ? DefaultDataDir : options.DataDir;
        var homeDir = string.IsNullOrWhiteSpace(options.HomeDir) ? DefaultHomeDir : options.HomeDir;
        var manifestsDir = string.IsNullOrWhiteSpace(options.ManifestsDir) ? DefaultBuiltinManifestsDir : options.ManifestsDir;
        var templateHooksDir = string.IsNullOrWhiteSpace(options.TemplateHooks) ? DefaultTemplateHooksDir : options.TemplateHooks;
        var workspaceHooksDir = string.IsNullOrWhiteSpace(options.WorkspaceHooks) ? DefaultWorkspaceHooksDir : options.WorkspaceHooks;
        var workspaceDir = string.IsNullOrWhiteSpace(options.WorkspaceDir) ? DefaultWorkspaceDir : options.WorkspaceDir;

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
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"[ERROR] {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"[ERROR] {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"[ERROR] {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (JsonException ex)
        {
            await stderr.WriteLineAsync($"[ERROR] {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (ArgumentException ex)
        {
            await stderr.WriteLineAsync($"[ERROR] {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (NotSupportedException ex)
        {
            await stderr.WriteLineAsync($"[ERROR] {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunLinkRepairCoreAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
    {
        var mode = ResolveLinkRepairMode(options);
        var quiet = options.Quiet;
        var builtinSpecPath = string.IsNullOrWhiteSpace(options.BuiltinSpec) ? DefaultBuiltinLinkSpec : options.BuiltinSpec;
        var userSpecPath = string.IsNullOrWhiteSpace(options.UserSpec) ? DefaultUserLinkSpec : options.UserSpec;
        var checkedAtFilePath = string.IsNullOrWhiteSpace(options.CheckedAtFile) ? DefaultCheckedAtFile : options.CheckedAtFile;

        if (!File.Exists(builtinSpecPath))
        {
            await stderr.WriteLineAsync($"ERROR: Built-in link spec not found: {builtinSpecPath}").ConfigureAwait(false);
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
                catch (InvalidOperationException ex)
                {
                    stats.Errors++;
                    await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {ex.Message}").ConfigureAwait(false);
                }
                catch (IOException ex)
                {
                    stats.Errors++;
                    await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {ex.Message}").ConfigureAwait(false);
                }
                catch (UnauthorizedAccessException ex)
                {
                    stats.Errors++;
                    await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {ex.Message}").ConfigureAwait(false);
                }
                catch (JsonException ex)
                {
                    stats.Errors++;
                    await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {ex.Message}").ConfigureAwait(false);
                }
                catch (ArgumentException ex)
                {
                    stats.Errors++;
                    await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {ex.Message}").ConfigureAwait(false);
                }
                catch (NotSupportedException ex)
                {
                    stats.Errors++;
                    await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {ex.Message}").ConfigureAwait(false);
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
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (JsonException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (ArgumentException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (NotSupportedException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunLinkWatcherCoreAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
    {
        var pollIntervalSeconds = 60;
        if (!string.IsNullOrWhiteSpace(options.PollInterval) &&
            (!int.TryParse(options.PollInterval, out pollIntervalSeconds) || pollIntervalSeconds < 1))
        {
            await stderr.WriteLineAsync("--poll-interval requires a positive integer value").ConfigureAwait(false);
            return 1;
        }

        var importedAtPath = string.IsNullOrWhiteSpace(options.ImportedAtFile) ? DefaultImportedAtFile : options.ImportedAtFile;
        var checkedAtPath = string.IsNullOrWhiteSpace(options.CheckedAtFile) ? DefaultCheckedAtFile : options.CheckedAtFile;
        var quiet = options.Quiet;

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
            var exitCode = await RunLinkRepairCoreAsync(
                new SystemLinkRepairCommandOptions(
                    Check: false,
                    Fix: true,
                    DryRun: false,
                    Quiet: true,
                    BuiltinSpec: null,
                    UserSpec: null,
                    CheckedAtFile: checkedAtPath),
                cancellationToken).ConfigureAwait(false);
            if (exitCode == 0)
            {
                await LogInfoAsync(quiet, "Repair completed successfully").ConfigureAwait(false);
            }
            else
            {
                await stderr.WriteLineAsync("[ERROR] Repair command failed").ConfigureAwait(false);
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
                await stderr.WriteLineAsync($"[WARN] Skipping invalid link spec entry in {specPath}").ConfigureAwait(false);
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
                await stderr.WriteLineAsync($"[CONFLICT] {linkPath} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
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
                await stderr.WriteLineAsync($"ERROR: Cannot fix - directory exists without R flag: {linkPath}").ConfigureAwait(false);
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

        await stdout.WriteLineAsync().ConfigureAwait(false);
        await stdout.WriteLineAsync(mode == LinkRepairMode.DryRun ? "=== Dry-Run Summary ===" : "=== Link Status Summary ===").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  OK:      {stats.Ok}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Broken:  {stats.Broken}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Missing: {stats.Missing}").ConfigureAwait(false);
        if (mode == LinkRepairMode.Fix)
        {
            await stdout.WriteLineAsync($"  Fixed:   {stats.Fixed}").ConfigureAwait(false);
        }
        else if (mode == LinkRepairMode.DryRun)
        {
            await stdout.WriteLineAsync($"  Would fix: {stats.Fixed}").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync($"  Errors:  {stats.Errors}").ConfigureAwait(false);
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
            catch (InvalidOperationException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Native init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (IOException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Native init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (UnauthorizedAccessException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Native init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (JsonException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Native init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (ArgumentException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Native init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (NotSupportedException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Native init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
        }
        else
        {
            await stderr.WriteLineAsync("[WARN] Built-in manifests not found, using fallback volume structure").ConfigureAwait(false);
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
            await stderr.WriteLineAsync("[WARN] .env is symlink - skipping").ConfigureAwait(false);
            return;
        }

        if (!File.Exists(envFilePath))
        {
            return;
        }

        try
        {
            using var stream = File.OpenRead(envFilePath);
        }
        catch (IOException)
        {
            await stderr.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
            return;
        }
        catch (UnauthorizedAccessException)
        {
            await stderr.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
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

            if (line.TrimStart().StartsWith('#'))
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
                await stderr.WriteLineAsync($"[WARN] line {index + 1}: invalid key '{key}' - skipping").ConfigureAwait(false);
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
            await stderr.WriteLineAsync($"[WARN] {newDir} is a symlink - cannot migrate git config").ConfigureAwait(false);
            return;
        }

        Directory.CreateDirectory(newDir);
        if (await IsSymlinkAsync(newPath).ConfigureAwait(false))
        {
            await stderr.WriteLineAsync($"[WARN] {newPath} is a symlink - cannot migrate git config").ConfigureAwait(false);
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

        var source = Path.Combine(dataDir, "git", "gitconfig");
        if (!File.Exists(source) || new FileInfo(source).Length == 0)
        {
            return;
        }

        if (Directory.Exists(destination))
        {
            await stderr.WriteLineAsync($"[WARN] Destination {destination} exists but is not a regular file - skipping").ConfigureAwait(false);
            return;
        }

        var tempDestination = $"{destination}.tmp.{Environment.ProcessId}";
        File.Copy(source, tempDestination, overwrite: true);
        File.Move(tempDestination, destination, overwrite: true);
        await LogInfoAsync(quiet, "Git config loaded from data volume").ConfigureAwait(false);
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
            await stderr.WriteLineAsync($"[WARN] CAI_HOST_WORKSPACE must be absolute path: {hostWorkspace}").ConfigureAwait(false);
            return;
        }

        if (!IsAllowedWorkspacePrefix(hostWorkspace))
        {
            await stderr.WriteLineAsync($"[WARN] CAI_HOST_WORKSPACE must be under /home/, /tmp/, /mnt/, /workspaces/, or /Users/: {hostWorkspace}").ConfigureAwait(false);
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
            _ = ManifestApplier.ApplyAgentShims(userManifestDirectory, "/opt/containai/user-agent-shims", "/usr/local/bin/cai");

            var userSpec = ManifestGenerators.GenerateContainerLinkSpec(userManifestDirectory);
            var userSpecPath = Path.Combine(dataDir, "containai", "user-link-spec.json");
            Directory.CreateDirectory(Path.GetDirectoryName(userSpecPath)!);
            await File.WriteAllTextAsync(userSpecPath, userSpec.Content).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
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
                await stderr.WriteLineAsync($"[WARN] Skipping non-executable hook: {hook}").ConfigureAwait(false);
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
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static async Task<bool> IsSymlinkAsync(string path)
    {
        var result = await RunProcessCaptureAsync("test", ["-L", path], null, CancellationToken.None).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private static async Task<string?> ReadLinkTargetAsync(string path)
    {
        var result = await RunProcessCaptureAsync("readlink", [path], null, CancellationToken.None).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return null;
        }

        return result.StandardOutput.Trim();
    }

    private static async Task<string?> TryReadTrimmedTextAsync(string path)
    {
        try
        {
            return (await File.ReadAllTextAsync(path).ConfigureAwait(false)).Trim();
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
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

    private static async Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments) => _ = await RunAsRootCaptureAsync(executable, arguments, null, CancellationToken.None).ConfigureAwait(false);

    private static async Task<ProcessCaptureResult> RunAsRootCaptureAsync(
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
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static LinkRepairMode ResolveLinkRepairMode(SystemLinkRepairCommandOptions options)
    {
        if (options.DryRun)
        {
            return LinkRepairMode.DryRun;
        }

        if (options.Fix)
        {
            return LinkRepairMode.Fix;
        }

        return LinkRepairMode.Check;
    }

    private async Task LogInfoAsync(bool quiet, string message)
    {
        if (quiet)
        {
            return;
        }

        await stdout.WriteLineAsync($"[INFO] {message}").ConfigureAwait(false);
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
        var result = await CliWrapProcessRunner
            .RunCaptureAsync(executable, arguments, cancellationToken, workingDirectory, standardInput)
            .ConfigureAwait(false);

        return new ProcessCaptureResult(result.ExitCode, result.StandardOutput, result.StandardError);
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
