namespace ContainAI.Cli.Host;

internal sealed partial class SessionSshBootstrapService
{
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

        var publicKey = await File.ReadAllTextAsync(SessionRuntimeInfrastructure.ResolveSshPublicKeyPath(), cancellationToken).ConfigureAwait(false);
        var keyLine = publicKey.Trim();
        if (string.IsNullOrWhiteSpace(keyLine))
        {
            return ResolutionResult<bool>.ErrorResult("SSH public key is empty.", 12);
        }

        var escapedKey = SessionRuntimeInfrastructure.EscapeForSingleQuotedShell(keyLine);
        var authorize = await SessionRuntimeInfrastructure.DockerCaptureAsync(
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
                $"Failed to install SSH public key: {SessionRuntimeInfrastructure.TrimOrFallback(authorize.StandardError, "docker exec failed")}",
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
