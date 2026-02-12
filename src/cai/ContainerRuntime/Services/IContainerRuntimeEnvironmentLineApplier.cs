namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeEnvironmentLineApplier
{
    Task ApplyLineIfValidAsync(string rawLine, int lineNumber);
}
