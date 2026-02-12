using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Paths;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host;

internal interface IImportRunContextResolver
{
    Task<ResolutionResult<ImportRunContext>> ResolveAsync(ImportCommandOptions options, CancellationToken cancellationToken);
}
