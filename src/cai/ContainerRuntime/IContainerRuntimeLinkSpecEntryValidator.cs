namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkSpecEntryValidator
{
    bool TryValidate(ContainerRuntimeLinkSpecRawEntry entry, out ContainerRuntimeLinkSpecValidatedEntry validatedEntry);
}
