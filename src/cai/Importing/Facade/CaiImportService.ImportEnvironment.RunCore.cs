using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportEnvironmentOperations
{
    public async Task<int> ImportEnvironmentVariablesAsync(
        string volume,
        string workspace,
        string? explicitConfigPath,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = ResolveEnvironmentConfigPath(workspace, explicitConfigPath);
        if (!File.Exists(configPath))
        {
            return 0;
        }

        var envParseResult = await TryLoadEnvironmentSectionAsync(configPath, cancellationToken).ConfigureAwait(false);
        if (!envParseResult.Success)
        {
            return envParseResult.ExitCode;
        }

        using var configDocument = envParseResult.Document!;
        var envSection = envParseResult.Section;
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
