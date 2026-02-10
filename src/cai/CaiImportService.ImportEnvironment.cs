using System.Text.Json;
using ContainAI.Cli.Host.Importing.Environment;

namespace ContainAI.Cli.Host;

internal interface IImportEnvironmentOperations
{
    Task<int> ImportEnvironmentVariablesAsync(
        string volume,
        string workspace,
        string? explicitConfigPath,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}

internal sealed class CaiImportEnvironmentOperations : CaiRuntimeSupport
    , IImportEnvironmentOperations
{
    internal const string EnvTargetSymlinkGuardMessage = ".env target is symlink";

    private readonly IImportEnvironmentValueOperations environmentValueOperations;

    public CaiImportEnvironmentOperations(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ImportEnvironmentValueOperations(standardOutput, standardError))
    {
    }

    internal CaiImportEnvironmentOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportEnvironmentValueOperations importEnvironmentValueOperations)
        : base(standardOutput, standardError)
        => environmentValueOperations = importEnvironmentValueOperations ?? throw new ArgumentNullException(nameof(importEnvironmentValueOperations));

    public async Task<int> ImportEnvironmentVariablesAsync(
        string volume,
        string workspace,
        string? explicitConfigPath,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : ResolveConfigPath(workspace);
        if (!File.Exists(configPath))
        {
            return 0;
        }

        var configResult = await RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (configResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(configResult.StandardError))
            {
                await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        if (!string.IsNullOrWhiteSpace(configResult.StandardError))
        {
            await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
        }

        using var configDocument = JsonDocument.Parse(configResult.StandardOutput);
        if (configDocument.RootElement.ValueKind != JsonValueKind.Object ||
            !configDocument.RootElement.TryGetProperty("env", out var envSection))
        {
            return 0;
        }

        if (envSection.ValueKind != JsonValueKind.Object)
        {
            await stderr.WriteLineAsync("[WARN] [env] section must be a table; skipping env import").ConfigureAwait(false);
            return 0;
        }

        var validatedKeys = await environmentValueOperations.ResolveValidatedImportKeysAsync(envSection, verbose, cancellationToken).ConfigureAwait(false);
        if (validatedKeys.Count == 0)
        {
            return 0;
        }

        var workspaceRoot = Path.GetFullPath(ExpandHomePath(workspace));
        var fileVariables = await environmentValueOperations.ResolveFileVariablesAsync(envSection, workspaceRoot, validatedKeys, cancellationToken).ConfigureAwait(false);
        if (fileVariables is null)
        {
            return 1;
        }

        var fromHost = await environmentValueOperations.ResolveFromHostFlagAsync(envSection, cancellationToken).ConfigureAwait(false);
        var merged = await environmentValueOperations.MergeVariablesWithHostValuesAsync(fileVariables, validatedKeys, fromHost, cancellationToken).ConfigureAwait(false);

        if (merged.Count == 0)
        {
            return 0;
        }

        if (dryRun)
        {
            foreach (var key in merged.Keys.OrderBy(static value => value, StringComparer.Ordinal))
            {
                await stdout.WriteLineAsync($"[DRY-RUN] env key: {key}").ConfigureAwait(false);
            }

            return 0;
        }

        return await environmentValueOperations.PersistMergedEnvironmentAsync(volume, validatedKeys, merged, cancellationToken).ConfigureAwait(false);
    }
}
