using System.Text.Json;
using ContainAI.Cli.Host.Importing.Environment;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal sealed class ImportEnvironmentMergePersistCoordinator
{
    private readonly IImportEnvironmentValueOperations environmentValueOperations;
    private readonly ImportEnvironmentDryRunReporter dryRunReporter;

    public ImportEnvironmentMergePersistCoordinator(
        IImportEnvironmentValueOperations importEnvironmentValueOperations,
        ImportEnvironmentDryRunReporter importEnvironmentDryRunReporter)
    {
        environmentValueOperations = importEnvironmentValueOperations ?? throw new ArgumentNullException(nameof(importEnvironmentValueOperations));
        dryRunReporter = importEnvironmentDryRunReporter ?? throw new ArgumentNullException(nameof(importEnvironmentDryRunReporter));
    }

    public async Task<int> MergeAndPersistAsync(
        string volume,
        string workspace,
        JsonElement envSection,
        IReadOnlyList<string> validatedKeys,
        bool dryRun,
        CancellationToken cancellationToken)
    {
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
            await dryRunReporter.ReportMergedKeysAsync(merged, cancellationToken).ConfigureAwait(false);
            return 0;
        }

        return await environmentValueOperations
            .PersistMergedEnvironmentAsync(volume, validatedKeys, merged, cancellationToken)
            .ConfigureAwait(false);
    }
}
