using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionContainerCreateStartOrchestrator
{
    Task<ResolutionResult<CreateContainerResult>> CreateContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken);

    Task<ResolutionResult<bool>> StartContainerAsync(
        string context,
        string containerName,
        CancellationToken cancellationToken);
}

internal sealed class SessionContainerCreateStartOrchestrator : ISessionContainerCreateStartOrchestrator
{
    private readonly TextWriter stderr;
    private readonly ISessionSshPortAllocator sshPortAllocator;
    private readonly ISessionContainerRunCommandBuilder runCommandBuilder;
    private readonly ISessionContainerDockerClient dockerClient;
    private readonly ISessionContainerStateWaiter stateWaiter;

    public SessionContainerCreateStartOrchestrator(
        TextWriter standardError,
        ISessionSshPortAllocator sessionSshPortAllocator,
        ISessionContainerRunCommandBuilder sessionContainerRunCommandBuilder,
        ISessionContainerDockerClient sessionContainerDockerClient,
        ISessionContainerStateWaiter sessionContainerStateWaiter)
    {
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        sshPortAllocator = sessionSshPortAllocator ?? throw new ArgumentNullException(nameof(sessionSshPortAllocator));
        runCommandBuilder = sessionContainerRunCommandBuilder ?? throw new ArgumentNullException(nameof(sessionContainerRunCommandBuilder));
        dockerClient = sessionContainerDockerClient ?? throw new ArgumentNullException(nameof(sessionContainerDockerClient));
        stateWaiter = sessionContainerStateWaiter ?? throw new ArgumentNullException(nameof(sessionContainerStateWaiter));
    }

    public async Task<ResolutionResult<CreateContainerResult>> CreateContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var sshPortResolution = await sshPortAllocator.AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
        if (!sshPortResolution.Success)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult(sshPortResolution.Error!, sshPortResolution.ErrorCode);
        }

        var sshPort = sshPortResolution.Value!;
        var image = SessionRuntimeDockerHelpers.ResolveImage(options);
        if (!string.IsNullOrWhiteSpace(options.Template))
        {
            await stderr.WriteLineAsync($"Template '{options.Template}' requested; using image '{image}' in native mode.").ConfigureAwait(false);
        }

        var dockerArgs = runCommandBuilder.BuildCommand(options, resolved, sshPort, image);

        var create = await dockerClient.CreateContainerAsync(
            resolved.Context,
            dockerArgs,
            cancellationToken).ConfigureAwait(false);
        if (create.ExitCode != 0)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult(
                $"Failed to create container: {SessionRuntimeTextHelpers.TrimOrFallback(create.StandardError, "docker run failed")}");
        }

        var waitRunning = await stateWaiter.WaitForContainerStateAsync(
            resolved.Context,
            resolved.ContainerName,
            "running",
            TimeSpan.FromSeconds(30),
            cancellationToken).ConfigureAwait(false);
        if (!waitRunning)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult($"Container '{resolved.ContainerName}' failed to start.");
        }

        return ResolutionResult<CreateContainerResult>.SuccessResult(new CreateContainerResult(sshPort));
    }

    public async Task<ResolutionResult<bool>> StartContainerAsync(
        string context,
        string containerName,
        CancellationToken cancellationToken)
    {
        var start = await dockerClient.StartContainerAsync(
            context,
            containerName,
            cancellationToken).ConfigureAwait(false);
        if (start.ExitCode != 0)
        {
            return ResolutionResult<bool>.ErrorResult(
                $"Failed to start container '{containerName}': {SessionRuntimeTextHelpers.TrimOrFallback(start.StandardError, "docker start failed")}");
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }
}
