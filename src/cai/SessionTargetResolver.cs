namespace ContainAI.Cli.Host;

internal static partial class SessionTargetResolver
{
    public static Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken)
        => SessionTargetResolutionPipeline.ResolveAsync(options, cancellationToken);

    public static Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionTargetDockerLookupService.ReadContainerLabelsAsync(containerName, context, cancellationToken);
}
