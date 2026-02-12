using System.Text.Json;
using ContainAI.Cli.Host.Importing.Environment.Source;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentSourceOperations
{
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
}
