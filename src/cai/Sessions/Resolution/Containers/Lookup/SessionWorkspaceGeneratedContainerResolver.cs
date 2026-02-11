namespace ContainAI.Cli.Host;

internal interface ISessionWorkspaceGeneratedContainerResolver
{
    Task<ContainerLookupResult> ResolveAsync(string workspace, string context, CancellationToken cancellationToken);
}

internal sealed class SessionWorkspaceGeneratedContainerResolver(
    ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService,
    ISessionDockerQueryRunner dockerQueryRunner) : ISessionWorkspaceGeneratedContainerResolver
{
    public async Task<ContainerLookupResult> ResolveAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var generated = await workspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var generatedExists = await dockerQueryRunner.QueryContainerInspectAsync(generated, context, cancellationToken).ConfigureAwait(false);

        return generatedExists.ExitCode == 0
            ? ContainerLookupResult.Success(generated)
            : ContainerLookupResult.Empty();
    }
}
