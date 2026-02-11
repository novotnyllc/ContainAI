namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDockerLookupService
{
    private static Task<ProcessResult> QueryContainerLabelFieldsAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--format", LabelInspectFormat, containerName],
            cancellationToken);

    private static Task<ProcessResult> QueryContainerInspectAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", containerName],
            cancellationToken);

    private static Task<ProcessResult> QueryContainersByWorkspaceLabelAsync(string workspace, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["ps", "-aq", "--filter", $"label={SessionRuntimeConstants.WorkspaceLabelKey}={workspace}"],
            cancellationToken);

    private static Task<ProcessResult> QueryContainerNameByIdAsync(string context, string containerId, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--format", "{{.Name}}", containerId],
            cancellationToken);

    private async Task<List<string>> FindContextsContainingContainerAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken)
    {
        var contexts = await workspaceDiscoveryService.BuildCandidateContextsAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        var foundContexts = new List<string>();

        foreach (var context in contexts)
        {
            var inspect = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "docker",
                ["--context", context, "inspect", "--type", "container", "--", containerName],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                foundContexts.Add(context);
            }
        }

        return foundContexts;
    }
}
