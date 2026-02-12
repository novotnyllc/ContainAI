using System.Text.Json;

namespace ContainAI.Cli.Host;

internal interface IContainerLinkSpecReader
{
    Task<ContainerLinkSpecReadResult> ReadLinkSpecAsync(
        string containerName,
        string specPath,
        bool required,
        CancellationToken cancellationToken);
}
