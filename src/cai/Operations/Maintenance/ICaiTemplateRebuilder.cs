using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiTemplateRebuilder
{
    Task<int> RebuildTemplatesAsync(string baseImage, CancellationToken cancellationToken);
}
