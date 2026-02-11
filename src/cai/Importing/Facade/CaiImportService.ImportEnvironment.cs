using System.Text.Json;
using ContainAI.Cli.Host.Importing.Environment;
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
    internal const string EnvTargetSymlinkGuardMessage = ".env target is symlink";

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IImportEnvironmentValueOperations environmentValueOperations;
    private readonly IImportEnvironmentSectionLoader environmentSectionLoader;

    public CaiImportEnvironmentOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportEnvironmentValueOperations(standardOutput, standardError),
            new ImportEnvironmentSectionLoader(standardError))
    {
    }

    internal CaiImportEnvironmentOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportEnvironmentValueOperations importEnvironmentValueOperations,
        IImportEnvironmentSectionLoader importEnvironmentSectionLoader)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        environmentValueOperations = importEnvironmentValueOperations ?? throw new ArgumentNullException(nameof(importEnvironmentValueOperations));
        environmentSectionLoader = importEnvironmentSectionLoader ?? throw new ArgumentNullException(nameof(importEnvironmentSectionLoader));
    }

    public async Task<int> ImportEnvironmentVariablesAsync(
        string volume,
        string workspace,
        string? explicitConfigPath,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = ImportEnvironmentConfigPathResolver.ResolveEnvironmentConfigPath(workspace, explicitConfigPath);
        if (!File.Exists(configPath))
        {
            return 0;
        }

        var envSectionResult = await environmentSectionLoader.LoadAsync(configPath, cancellationToken).ConfigureAwait(false);
        if (!envSectionResult.Success)
        {
            return envSectionResult.ExitCode;
        }

        using var configDocument = envSectionResult.Document!;
        var envSection = envSectionResult.Section;
        if (envSection.ValueKind != JsonValueKind.Object)
        {
            await stderr.WriteLineAsync("[WARN] [env] section must be a table; skipping env import").ConfigureAwait(false);
            return 0;
        }

        var validatedKeys = await environmentValueOperations
            .ResolveValidatedImportKeysAsync(envSection, verbose, cancellationToken)
            .ConfigureAwait(false);

        if (validatedKeys.Count == 0)
        {
            return 0;
        }

        var workspaceRoot = Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(workspace));
        var fileVariables = await environmentValueOperations
            .ResolveFileVariablesAsync(envSection, workspaceRoot, validatedKeys, cancellationToken)
            .ConfigureAwait(false);
        if (fileVariables is null)
        {
            return 1;
        }

        var fromHost = await environmentValueOperations
            .ResolveFromHostFlagAsync(envSection, cancellationToken)
            .ConfigureAwait(false);

        var merged = await environmentValueOperations
            .MergeVariablesWithHostValuesAsync(fileVariables, validatedKeys, fromHost, cancellationToken)
            .ConfigureAwait(false);

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

        return await environmentValueOperations
            .PersistMergedEnvironmentAsync(volume, validatedKeys, merged, cancellationToken)
            .ConfigureAwait(false);
    }
}
