namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal sealed record ExistingContainerAttachment(
    bool Exists,
    string? State,
    string? SshPort)
{
    internal static readonly ExistingContainerAttachment NotFound = new(
        Exists: false,
        State: null,
        SshPort: null);
}
