namespace ContainAI.Cli.Host;

internal sealed partial class ContainAiDockerProxyService
{
    private async Task<int> RunCreateAsync(
        IReadOnlyList<string> dockerArgs,
        DockerProxyWrapperFlags wrapperFlags,
        string contextName,
        TextWriter stderr,
        CancellationToken cancellationToken)
    {
        var createParseResult = await DockerProxyCreateCommandRequestParser.ParseAsync(
            dockerArgs,
            contextName,
            argumentParser,
            featureSettingsParser,
            commandExecutor,
            environment,
            stderr,
            cancellationToken).ConfigureAwait(false);

        if (createParseResult.Status == DockerProxyCreateCommandParseStatus.Passthrough)
        {
            return await commandExecutor.RunInteractiveAsync(dockerArgs, stderr, cancellationToken).ConfigureAwait(false);
        }

        if (createParseResult.Status == DockerProxyCreateCommandParseStatus.SetupMissing)
        {
            return 1;
        }

        var request = createParseResult.Request!;

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
