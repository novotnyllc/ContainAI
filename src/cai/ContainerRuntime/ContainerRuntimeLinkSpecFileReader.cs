namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkSpecFileReader
{
    Task<string> ReadAllTextAsync(string specPath, CancellationToken cancellationToken);
}

internal sealed class ContainerRuntimeLinkSpecFileReader : IContainerRuntimeLinkSpecFileReader
{
    public Task<string> ReadAllTextAsync(string specPath, CancellationToken cancellationToken)
        => File.ReadAllTextAsync(specPath, cancellationToken);
}
