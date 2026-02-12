using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal sealed class SessionDockerQueryRunner : ISessionDockerQueryRunner
{
    private const string LabelInspectFormat =
        "{{index .Config.Labels \"containai.managed\"}}|{{index .Config.Labels \"containai.workspace\"}}|{{index .Config.Labels \"containai.data-volume\"}}|{{index .Config.Labels \"containai.ssh-port\"}}|{{.Config.Image}}|{{.State.Status}}";

    private readonly ISessionRuntimeOperations runtimeOperations;

    public SessionDockerQueryRunner()
        : this(new SessionRuntimeOperations())
    {
    }

    internal SessionDockerQueryRunner(ISessionRuntimeOperations sessionRuntimeOperations)
        => runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));

    public Task<ProcessResult> QueryContainerLabelFieldsAsync(string containerName, string context, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(
            context,
            ["inspect", "--format", LabelInspectFormat, containerName],
            cancellationToken);

    public Task<ProcessResult> QueryContainerInspectAsync(string containerName, string context, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", containerName],
            cancellationToken);

    public Task<ProcessResult> QueryContainersByWorkspaceLabelAsync(string workspace, string context, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(
            context,
            ["ps", "-aq", "--filter", $"label={SessionRuntimeConstants.WorkspaceLabelKey}={workspace}"],
            cancellationToken);

    public Task<ProcessResult> QueryContainerNameByIdAsync(string context, string containerId, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(
            context,
            ["inspect", "--format", "{{.Name}}", containerId],
            cancellationToken);

    public Task<List<string>> FindContextsContainingContainerAsync(
        string containerName,
        IReadOnlyList<string> contexts,
        CancellationToken cancellationToken)
        => FindContextsContainingContainerCoreAsync(containerName, contexts, cancellationToken);

    private async Task<List<string>> FindContextsContainingContainerCoreAsync(
        string containerName,
        IReadOnlyList<string> contexts,
        CancellationToken cancellationToken)
    {
        var foundContexts = new List<string>();

        foreach (var context in contexts)
        {
            var inspect = await runtimeOperations.RunProcessCaptureAsync(
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
