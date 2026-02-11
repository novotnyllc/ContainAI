namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDockerLookupService
{
    public async Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
    {
        var inspect = await QueryContainerLabelFieldsAsync(containerName, context, cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return ContainerLabelState.NotFound();
        }

        if (!TryParseContainerLabelFields(inspect.StandardOutput, out var parsed))
        {
            return ContainerLabelState.NotFound();
        }

        return BuildContainerLabelState(parsed);
    }

    public async Task<FindContainerByNameResult> FindContainerByNameAcrossContextsAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken)
    {
        var contextsContainingContainer = await FindContextsContainingContainerAsync(
            containerName,
            explicitConfig,
            workspace,
            cancellationToken).ConfigureAwait(false);

        return SelectContainerContextCandidate(containerName, contextsContainingContainer);
    }

    public async Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var configuredContainer = await TryResolveConfiguredWorkspaceContainerAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (configuredContainer is not null)
        {
            return configuredContainer;
        }

        var (continueSearch, byLabel) = await TryResolveWorkspaceContainerByLabelAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (!continueSearch)
        {
            return byLabel;
        }

        return await TryResolveGeneratedWorkspaceContainerAsync(workspace, context, cancellationToken).ConfigureAwait(false);
    }

    public async Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var baseName = await workspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        return await ResolveNameWithCollisionHandlingAsync(workspace, context, baseName, cancellationToken).ConfigureAwait(false);
    }
}
