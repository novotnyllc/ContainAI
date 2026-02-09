using System.Text.Json;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task<int> RunInitCoreAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        var parsed = ParseInitCommandOptions(options);
        var quiet = parsed.Quiet;
        var dataDir = parsed.DataDir;
        var homeDir = parsed.HomeDir;
        var manifestsDir = parsed.ManifestsDir;
        var templateHooksDir = parsed.TemplateHooksDir;
        var workspaceHooksDir = parsed.WorkspaceHooksDir;
        var workspaceDir = parsed.WorkspaceDir;

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
        var parsed = ParseLinkRepairCommandOptions(options);
        var mode = parsed.Mode;
        var quiet = parsed.Quiet;
        var builtinSpecPath = parsed.BuiltinSpecPath;
        var userSpecPath = parsed.UserSpecPath;
        var checkedAtFilePath = parsed.CheckedAtFilePath;

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
        var parsed = ParseWatchLinksCommandOptions(options);
        if (!parsed.IsValid)
        {
            await stderr.WriteLineAsync(parsed.ErrorMessage).ConfigureAwait(false);
            return 1;
        }

        var pollIntervalSeconds = parsed.PollIntervalSeconds;
        var importedAtPath = parsed.ImportedAtPath;
        var checkedAtPath = parsed.CheckedAtPath;
        var quiet = parsed.Quiet;

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
