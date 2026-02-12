using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal sealed class SessionContainerLabelReader : ISessionContainerLabelReader
{
    private readonly ISessionDockerQueryRunner dockerQueryRunner;

    public SessionContainerLabelReader()
        : this(new SessionDockerQueryRunner())
    {
    }

    internal SessionContainerLabelReader(ISessionDockerQueryRunner sessionDockerQueryRunner)
        => dockerQueryRunner = sessionDockerQueryRunner ?? throw new ArgumentNullException(nameof(sessionDockerQueryRunner));

    public async Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
    {
        var inspect = await dockerQueryRunner
            .QueryContainerLabelFieldsAsync(containerName, context, cancellationToken)
            .ConfigureAwait(false);

        return SessionTargetDockerLookupParsing.TryParseContainerLabelFields(inspect.StandardOutput, inspect.ExitCode, out var parsed)
            ? SessionTargetDockerLookupParsing.BuildContainerLabelState(parsed)
            : ContainerLabelState.NotFound();
    }
}
