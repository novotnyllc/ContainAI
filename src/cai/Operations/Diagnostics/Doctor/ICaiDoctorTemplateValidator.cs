using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorTemplateValidator
{
    Task<bool> ResolveTemplateStatusAsync(bool buildTemplates, CancellationToken cancellationToken);
}
