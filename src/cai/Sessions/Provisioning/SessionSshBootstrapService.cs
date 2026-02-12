using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal sealed class SessionSshBootstrapService : ISessionSshBootstrapService
{
    private readonly ISessionSshLocalConfigService localConfigService;
    private readonly ISessionSshPortReadinessService portReadinessService;
    private readonly ISessionRuntimeOperations runtimeOperations;

    public SessionSshBootstrapService()
        : this(new SessionSshLocalConfigService(), new SessionSshPortReadinessService(), new SessionRuntimeOperations())
    {
    }

    internal SessionSshBootstrapService(
        ISessionSshLocalConfigService sessionSshLocalConfigService,
        ISessionSshPortReadinessService sessionSshPortReadinessService)
        : this(sessionSshLocalConfigService, sessionSshPortReadinessService, new SessionRuntimeOperations())
    {
    }

    internal SessionSshBootstrapService(
        ISessionSshLocalConfigService sessionSshLocalConfigService,
        ISessionSshPortReadinessService sessionSshPortReadinessService,
        ISessionRuntimeOperations sessionRuntimeOperations)
    {
        localConfigService = sessionSshLocalConfigService ?? throw new ArgumentNullException(nameof(sessionSshLocalConfigService));
        portReadinessService = sessionSshPortReadinessService ?? throw new ArgumentNullException(nameof(sessionSshPortReadinessService));
        runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));
    }

    public async Task<ResolutionResult<bool>> EnsureSshBootstrapAsync(
        ResolvedTarget resolved,
        string sshPort,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(sshPort))
        {
            return ResolutionResult<bool>.ErrorResult("Container has no SSH port configured.");
        }

        var keyResult = await localConfigService.EnsureSshKeyPairAsync(cancellationToken).ConfigureAwait(false);
        if (!keyResult.Success)
        {
            return ResolutionResult<bool>.ErrorResult(keyResult.Error!, keyResult.ErrorCode);
        }

        var waitReady = await portReadinessService.WaitForSshPortAsync(sshPort, cancellationToken).ConfigureAwait(false);
        if (!waitReady)
        {
            return ResolutionResult<bool>.ErrorResult($"SSH port {sshPort} is not ready for container '{resolved.ContainerName}'.", 12);
        }

        var publicKey = await File.ReadAllTextAsync(runtimeOperations.ResolveSshPublicKeyPath(), cancellationToken).ConfigureAwait(false);
        var keyLine = publicKey.Trim();
        if (string.IsNullOrWhiteSpace(keyLine))
        {
            return ResolutionResult<bool>.ErrorResult("SSH public key is empty.", 12);
        }

        var escapedKey = runtimeOperations.EscapeForSingleQuotedShell(keyLine);
        var authorize = await runtimeOperations.DockerCaptureAsync(
            resolved.Context,
            [
                "exec",
                resolved.ContainerName,
                "sh",
                "-lc",
                $"mkdir -p /home/agent/.ssh && chmod 700 /home/agent/.ssh && touch /home/agent/.ssh/authorized_keys && grep -qxF '{escapedKey}' /home/agent/.ssh/authorized_keys || printf '%s\\n' '{escapedKey}' >> /home/agent/.ssh/authorized_keys; chown -R agent:agent /home/agent/.ssh; chmod 600 /home/agent/.ssh/authorized_keys",
            ],
            cancellationToken).ConfigureAwait(false);

        if (authorize.ExitCode != 0)
        {
            return ResolutionResult<bool>.ErrorResult(
                $"Failed to install SSH public key: {runtimeOperations.TrimOrFallback(authorize.StandardError, "docker exec failed")}",
                12);
        }

        var knownHosts = await localConfigService.UpdateKnownHostsAsync(resolved.ContainerName, sshPort, cancellationToken).ConfigureAwait(false);
        if (!knownHosts.Success)
        {
            return ResolutionResult<bool>.ErrorResult(knownHosts.Error!, knownHosts.ErrorCode);
        }

        var sshConfig = await localConfigService.EnsureSshHostConfigAsync(resolved.ContainerName, sshPort, cancellationToken).ConfigureAwait(false);
        if (!sshConfig.Success)
        {
            return ResolutionResult<bool>.ErrorResult(sshConfig.Error!, sshConfig.ErrorCode);
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }
}
