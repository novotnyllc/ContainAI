using System.Text.Json;
using ContainAI.Cli.Host.Importing.Environment;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

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

internal sealed class CaiImportEnvironmentOperations : IImportEnvironmentOperations
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    internal const string EnvTargetSymlinkGuardMessage = ".env target is symlink";

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IImportEnvironmentValueOperations environmentValueOperations;

    public CaiImportEnvironmentOperations(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ImportEnvironmentValueOperations(standardOutput, standardError))
    {
    }

    internal CaiImportEnvironmentOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportEnvironmentValueOperations importEnvironmentValueOperations)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        environmentValueOperations = importEnvironmentValueOperations ?? throw new ArgumentNullException(nameof(importEnvironmentValueOperations));
    }

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

        var workspaceRoot = Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(workspace));
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

    private static string ResolveEnvironmentConfigPath(string workspace, string? explicitConfigPath)
        => !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : CaiRuntimeConfigLocator.ResolveConfigPath(workspace, ConfigFileNames);

    private async Task<EnvironmentSectionParseResult> TryLoadEnvironmentSectionAsync(string configPath, CancellationToken cancellationToken)
    {
        var configResult = await CaiRuntimeParseAndTimeHelpers
            .RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken)
            .ConfigureAwait(false);
        if (configResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(configResult.StandardError))
            {
                await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return EnvironmentSectionParseResult.FromFailure(1);
        }

        if (!string.IsNullOrWhiteSpace(configResult.StandardError))
        {
            await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
        }

        var configDocument = JsonDocument.Parse(configResult.StandardOutput);
        if (configDocument.RootElement.ValueKind != JsonValueKind.Object ||
            !configDocument.RootElement.TryGetProperty("env", out var envSection))
        {
            configDocument.Dispose();
            return EnvironmentSectionParseResult.FromFailure(0);
        }

        return EnvironmentSectionParseResult.FromSuccess(configDocument, envSection);
    }

    private readonly record struct EnvironmentSectionParseResult(
        bool Success,
        int ExitCode,
        JsonDocument? Document,
        JsonElement Section)
    {
        public static EnvironmentSectionParseResult FromSuccess(JsonDocument document, JsonElement section)
            => new(true, 0, document, section);

        public static EnvironmentSectionParseResult FromFailure(int exitCode)
            => new(false, exitCode, null, default);
    }
}
