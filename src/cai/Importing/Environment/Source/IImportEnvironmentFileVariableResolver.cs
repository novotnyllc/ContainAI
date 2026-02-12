using System.Text.Json;
using ContainAI.Cli.Host.RuntimeSupport.Environment;

namespace ContainAI.Cli.Host.Importing.Environment.Source;

internal interface IImportEnvironmentFileVariableResolver
{
    Task<Dictionary<string, string>?> ResolveAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken);
}
