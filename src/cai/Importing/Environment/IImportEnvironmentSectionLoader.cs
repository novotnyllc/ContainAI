using System.Text.Json;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentSectionLoader
{
    Task<ImportEnvironmentSectionLoadResult> LoadAsync(string configPath, CancellationToken cancellationToken);
}
