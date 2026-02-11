namespace ContainAI.Cli.Host;

internal interface ISessionDockerQueryRunner
{
    Task<ProcessResult> QueryContainerLabelFieldsAsync(string containerName, string context, CancellationToken cancellationToken);

    Task<ProcessResult> QueryContainerInspectAsync(string containerName, string context, CancellationToken cancellationToken);

    Task<ProcessResult> QueryContainersByWorkspaceLabelAsync(string workspace, string context, CancellationToken cancellationToken);

    Task<ProcessResult> QueryContainerNameByIdAsync(string context, string containerId, CancellationToken cancellationToken);

    Task<List<string>> FindContextsContainingContainerAsync(
        string containerName,
        IReadOnlyList<string> contexts,
        CancellationToken cancellationToken);
}

internal sealed class SessionDockerQueryRunner : ISessionDockerQueryRunner
{
    public Task<ProcessResult> QueryContainerLabelFieldsAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionTargetDockerLookupQueries.QueryContainerLabelFieldsAsync(containerName, context, cancellationToken);

    public Task<ProcessResult> QueryContainerInspectAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionTargetDockerLookupQueries.QueryContainerInspectAsync(containerName, context, cancellationToken);

    public Task<ProcessResult> QueryContainersByWorkspaceLabelAsync(string workspace, string context, CancellationToken cancellationToken)
        => SessionTargetDockerLookupQueries.QueryContainersByWorkspaceLabelAsync(workspace, context, cancellationToken);

    public Task<ProcessResult> QueryContainerNameByIdAsync(string context, string containerId, CancellationToken cancellationToken)
        => SessionTargetDockerLookupQueries.QueryContainerNameByIdAsync(context, containerId, cancellationToken);

    public Task<List<string>> FindContextsContainingContainerAsync(
        string containerName,
        IReadOnlyList<string> contexts,
        CancellationToken cancellationToken)
        => SessionTargetDockerLookupQueries.FindContextsContainingContainerAsync(containerName, contexts, cancellationToken);
}
