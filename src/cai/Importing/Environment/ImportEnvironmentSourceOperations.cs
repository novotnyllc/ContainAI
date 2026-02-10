using System.Text.Json;

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

internal sealed partial class ImportEnvironmentSourceOperations : CaiRuntimeSupport
    , IImportEnvironmentSourceOperations
{
    public ImportEnvironmentSourceOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }
}
