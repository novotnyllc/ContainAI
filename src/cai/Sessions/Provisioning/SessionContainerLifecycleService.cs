using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal sealed class SessionContainerLifecycleService : ISessionContainerLifecycleService
{
    private readonly ISessionSshPortAllocator sshPortAllocator;
    private readonly SessionContainerCreateStartOrchestrator createStartOrchestrator;
    private readonly SessionContainerDockerClient dockerClient;

    public SessionContainerLifecycleService()
        : this(TextWriter.Null, new SessionSshPortAllocator())
    {
    }

    internal SessionContainerLifecycleService(
        TextWriter standardError,
        ISessionSshPortAllocator sessionSshPortAllocator)
    {
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(sessionSshPortAllocator);

        sshPortAllocator = sessionSshPortAllocator;

        dockerClient = new SessionContainerDockerClient();
        createStartOrchestrator = new SessionContainerCreateStartOrchestrator(
            standardError,
            sessionSshPortAllocator,
            new SessionContainerRunCommandBuilder(),
            dockerClient,
            new SessionContainerStateWaiter(dockerClient));
    }

    public async Task<ResolutionResult<string>> CreateOrStartContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        ExistingContainerAttachment attachment,
        CancellationToken cancellationToken)
    {
        if (!attachment.Exists)
        {
            var created = await createStartOrchestrator.CreateContainerAsync(options, resolved, cancellationToken).ConfigureAwait(false);
            if (!created.Success)
            {
                return ResolutionResult<string>.ErrorResult(created.Error!, created.ErrorCode);
            }

            return ResolutionResult<string>.SuccessResult(created.Value!.SshPort);
        }

        var sshPort = attachment.SshPort ?? string.Empty;
        if (string.IsNullOrWhiteSpace(sshPort))
        {
            var allocated = await sshPortAllocator.AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
            if (!allocated.Success)
            {
                return allocated;
            }

            sshPort = allocated.Value!;
        }

        if (!string.Equals(attachment.State, "running", StringComparison.Ordinal))
        {
            var start = await createStartOrchestrator.StartContainerAsync(
                resolved.Context,
                resolved.ContainerName,
                cancellationToken).ConfigureAwait(false);
            if (!start.Success)
            {
                return ResolutionResult<string>.ErrorResult(start.Error!, start.ErrorCode);
            }
        }

        return ResolutionResult<string>.SuccessResult(sshPort);
    }

    public async Task RemoveContainerAsync(string context, string containerName, CancellationToken cancellationToken)
    {
        await dockerClient.StopContainerAsync(context, containerName, cancellationToken).ConfigureAwait(false);
        await dockerClient.RemoveContainerAsync(context, containerName, cancellationToken).ConfigureAwait(false);
    }
}
