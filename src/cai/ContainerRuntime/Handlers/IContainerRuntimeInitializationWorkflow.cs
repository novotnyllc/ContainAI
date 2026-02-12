using ContainAI.Cli.Host.ContainerRuntime.Configuration;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeInitializationWorkflow
{
    Task RunAsync(InitCommandParsing options, CancellationToken cancellationToken);
}
