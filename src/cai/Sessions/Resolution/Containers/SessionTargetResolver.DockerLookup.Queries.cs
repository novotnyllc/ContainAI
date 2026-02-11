namespace ContainAI.Cli.Host;

internal static class SessionTargetDockerLookupQueries
{
    private const string LabelInspectFormat =
        "{{index .Config.Labels \"containai.managed\"}}|{{index .Config.Labels \"containai.workspace\"}}|{{index .Config.Labels \"containai.data-volume\"}}|{{index .Config.Labels \"containai.ssh-port\"}}|{{.Config.Image}}|{{.State.Status}}";

    internal static Task<ProcessResult> QueryContainerLabelFieldsAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--format", LabelInspectFormat, containerName],
            cancellationToken);

    internal static Task<ProcessResult> QueryContainerInspectAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", containerName],
            cancellationToken);

    internal static Task<ProcessResult> QueryContainersByWorkspaceLabelAsync(string workspace, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["ps", "-aq", "--filter", $"label={SessionRuntimeConstants.WorkspaceLabelKey}={workspace}"],
            cancellationToken);

    internal static Task<ProcessResult> QueryContainerNameByIdAsync(string context, string containerId, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--format", "{{.Name}}", containerId],
            cancellationToken);

    internal static async Task<List<string>> FindContextsContainingContainerAsync(
        string containerName,
        IReadOnlyList<string> contexts,
        CancellationToken cancellationToken)
    {
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
