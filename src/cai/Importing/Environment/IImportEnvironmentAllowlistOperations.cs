using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentAllowlistOperations
{
    Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken);
}
