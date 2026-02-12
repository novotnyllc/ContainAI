using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment.Source;

internal interface IImportEnvironmentFromHostFlagResolver
{
    Task<bool> ResolveAsync(JsonElement envSection, CancellationToken cancellationToken);
}
