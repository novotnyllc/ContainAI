using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal interface ICaiVersionCommandWriter
{
    Task<int> WriteVersionAsync(bool json, CancellationToken cancellationToken);
}
