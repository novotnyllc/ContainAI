using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentValueOperations
{
    Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken);

    Task<Dictionary<string, string>?> ResolveFileVariablesAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken);

    Task<bool> ResolveFromHostFlagAsync(JsonElement envSection, CancellationToken cancellationToken);

    Task<Dictionary<string, string>> MergeVariablesWithHostValuesAsync(
        Dictionary<string, string> fileVariables,
        IReadOnlyList<string> validatedKeys,
        bool fromHost,
        CancellationToken cancellationToken);

    Task<int> PersistMergedEnvironmentAsync(
        string volume,
        IReadOnlyList<string> validatedKeys,
        Dictionary<string, string> merged,
        CancellationToken cancellationToken);
}
