using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal interface ICaiDockerCommandForwarder
{
    Task<int> RunAsync(IReadOnlyList<string> dockerArguments, CancellationToken cancellationToken);
}
