namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkSpecEntryValidator : IContainerRuntimeLinkSpecEntryValidator
{
    public bool TryValidate(ContainerRuntimeLinkSpecRawEntry entry, out ContainerRuntimeLinkSpecValidatedEntry validatedEntry)
    {
        if (string.IsNullOrWhiteSpace(entry.LinkPath) || string.IsNullOrWhiteSpace(entry.TargetPath))
        {
            validatedEntry = default;
            return false;
        }

        validatedEntry = new ContainerRuntimeLinkSpecValidatedEntry(entry.LinkPath, entry.TargetPath, entry.RemoveFirst);
        return true;
    }
}
