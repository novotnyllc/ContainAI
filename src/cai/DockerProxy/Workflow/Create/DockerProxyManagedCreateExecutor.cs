namespace ContainAI.Cli.Host;

internal sealed class DockerProxyManagedCreateExecutor(
    IDockerProxyArgumentParser argumentParser,
    IDockerProxyCommandExecutor commandExecutor,
    IDockerProxyPortAllocator portAllocator,
    IDockerProxyVolumeCredentialValidator volumeCredentialValidator,
    IDockerProxySshConfigUpdater sshConfigUpdater,
    IUtcClock clock)
{
    public async Task<int> ExecuteAsync(
        IReadOnlyList<string> dockerArgs,
        DockerProxyWrapperFlags wrapperFlags,
        string contextName,
        DockerProxyCreateCommandRequest request,
        TextWriter stderr,
        CancellationToken cancellationToken)
    {
        var sshPort = await portAllocator.AllocateSshPortAsync(
            request.LockPath,
            request.ContainAiConfigDir,
            contextName,
            request.Workspace.Name,
            request.Workspace.SanitizedName,
            cancellationToken).ConfigureAwait(false);

        var mountVolume = await volumeCredentialValidator.ValidateAsync(
            contextName,
            request.Settings.DataVolume,
            request.Settings.EnableCredentials,
            wrapperFlags.Quiet,
            stderr,
            cancellationToken).ConfigureAwait(false);

        var modifiedArgs = await DockerProxyCreateCommandOutputBuilder.BuildManagedCreateArgumentsAsync(
            dockerArgs,
            contextName,
            request.Workspace.Name,
            request.Settings,
            sshPort,
            mountVolume,
            wrapperFlags.Quiet,
            commandExecutor,
            clock,
            stderr,
            cancellationToken).ConfigureAwait(false);

        await sshConfigUpdater
            .UpdateAsync(request.Workspace.SanitizedName, sshPort, request.Settings.RemoteUser, stderr, cancellationToken)
            .ConfigureAwait(false);
        await DockerProxyCreateCommandOutputBuilder
            .WriteVerboseExecutionAsync(wrapperFlags.Verbose, wrapperFlags.Quiet, contextName, modifiedArgs, stderr)
            .ConfigureAwait(false);

        return await commandExecutor.RunInteractiveAsync(
            argumentParser.PrependContext(contextName, modifiedArgs),
            stderr,
            cancellationToken).ConfigureAwait(false);
    }
}
