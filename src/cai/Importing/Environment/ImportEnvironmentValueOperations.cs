using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed class ImportEnvironmentValueOperations : CaiRuntimeSupport
    , IImportEnvironmentValueOperations
{
    private readonly IImportEnvironmentAllowlistOperations allowlistOperations;
    private readonly IImportEnvironmentSourceOperations sourceOperations;
    private readonly IImportEnvironmentPersistenceOperations persistenceOperations;

    public ImportEnvironmentValueOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportEnvironmentAllowlistOperations(standardOutput, standardError),
            new ImportEnvironmentSourceOperations(standardOutput, standardError),
            new ImportEnvironmentPersistenceOperations(standardOutput, standardError))
    {
    }

    internal ImportEnvironmentValueOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportEnvironmentAllowlistOperations importEnvironmentAllowlistOperations,
        IImportEnvironmentSourceOperations importEnvironmentSourceOperations,
        IImportEnvironmentPersistenceOperations importEnvironmentPersistenceOperations)
        : base(standardOutput, standardError)
    {
        allowlistOperations = importEnvironmentAllowlistOperations ?? throw new ArgumentNullException(nameof(importEnvironmentAllowlistOperations));
        sourceOperations = importEnvironmentSourceOperations ?? throw new ArgumentNullException(nameof(importEnvironmentSourceOperations));
        persistenceOperations = importEnvironmentPersistenceOperations ?? throw new ArgumentNullException(nameof(importEnvironmentPersistenceOperations));
    }

    public Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken)
        => allowlistOperations.ResolveValidatedImportKeysAsync(envSection, verbose, cancellationToken);

    public Task<Dictionary<string, string>?> ResolveFileVariablesAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken)
        => sourceOperations.ResolveFileVariablesAsync(envSection, workspaceRoot, validatedKeys, cancellationToken);

    public Task<bool> ResolveFromHostFlagAsync(JsonElement envSection, CancellationToken cancellationToken)
        => sourceOperations.ResolveFromHostFlagAsync(envSection, cancellationToken);

    public Task<Dictionary<string, string>> MergeVariablesWithHostValuesAsync(
        Dictionary<string, string> fileVariables,
        IReadOnlyList<string> validatedKeys,
        bool fromHost,
        CancellationToken cancellationToken)
        => sourceOperations.MergeVariablesWithHostValuesAsync(fileVariables, validatedKeys, fromHost, cancellationToken);

    public Task<int> PersistMergedEnvironmentAsync(
        string volume,
        IReadOnlyList<string> validatedKeys,
        Dictionary<string, string> merged,
        CancellationToken cancellationToken)
        => persistenceOperations.PersistMergedEnvironmentAsync(volume, validatedKeys, merged, cancellationToken);
}
