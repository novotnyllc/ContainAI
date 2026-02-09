using System.Text.Json;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
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
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
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
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (IOException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (UnauthorizedAccessException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (JsonException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (ArgumentException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (NotSupportedException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
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
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
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

    private Task<int> RunSystemDevcontainerInstallCoreAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
        => devcontainerRuntime.RunInstallAsync(options, cancellationToken);

    private Task<int> RunSystemDevcontainerInitCoreAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunInitAsync(cancellationToken);

    private Task<int> RunSystemDevcontainerStartCoreAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunStartAsync(cancellationToken);

    private Task<int> RunSystemDevcontainerVerifySysboxCoreAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunVerifySysboxAsync(cancellationToken);
}
