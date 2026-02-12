using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiBaseImageResolver
{
    Task<string> ResolveBaseImageAsync(CancellationToken cancellationToken);
}
