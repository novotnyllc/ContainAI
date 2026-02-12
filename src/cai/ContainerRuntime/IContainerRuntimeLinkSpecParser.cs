namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkSpecParser
{
    IReadOnlyList<ContainerRuntimeLinkSpecRawEntry> ParseEntries(string specPath, string specJson);
}
