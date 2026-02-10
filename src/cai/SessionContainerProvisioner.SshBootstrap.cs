namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private static async Task<ResolutionResult<bool>> EnsureSshBootstrapAsync(
        ResolvedTarget resolved,
        string sshPort,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(sshPort))
        {
            return ErrorResult<bool>("Container has no SSH port configured.");
        }

        var keyResult = await EnsureSshKeyPairAsync(cancellationToken).ConfigureAwait(false);
        if (!keyResult.Success)
        {
            return ErrorFrom<bool, bool>(keyResult);
        }

        var waitReady = await WaitForSshPortAsync(sshPort, cancellationToken).ConfigureAwait(false);
        if (!waitReady)
        {
            return ErrorResult<bool>($"SSH port {sshPort} is not ready for container '{resolved.ContainerName}'.", 12);
        }

        var publicKey = await File.ReadAllTextAsync(SessionRuntimeInfrastructure.ResolveSshPublicKeyPath(), cancellationToken).ConfigureAwait(false);
        var keyLine = publicKey.Trim();
        if (string.IsNullOrWhiteSpace(keyLine))
        {
            return ErrorResult<bool>("SSH public key is empty.", 12);
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
            return ErrorResult<bool>(
                $"Failed to install SSH public key: {SessionRuntimeInfrastructure.TrimOrFallback(authorize.StandardError, "docker exec failed")}",
                12);
        }

        var knownHosts = await UpdateKnownHostsAsync(resolved.ContainerName, sshPort, cancellationToken).ConfigureAwait(false);
        if (!knownHosts.Success)
        {
            return ErrorFrom<bool, bool>(knownHosts);
        }

        var sshConfig = await EnsureSshHostConfigAsync(resolved.ContainerName, sshPort, cancellationToken).ConfigureAwait(false);
        if (!sshConfig.Success)
        {
            return ErrorFrom<bool, bool>(sshConfig);
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }

}
