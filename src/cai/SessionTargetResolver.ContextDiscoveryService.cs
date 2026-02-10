namespace ContainAI.Cli.Host;

internal interface ISessionTargetContextDiscoveryService
{
    Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken);

    Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken);
}

internal sealed class SessionTargetContextDiscoveryService : ISessionTargetContextDiscoveryService
{
    private const string DefaultContextName = "default";
    private readonly ISessionTargetConfiguredContextResolver configuredContextResolver;

    internal SessionTargetContextDiscoveryService(ISessionTargetConfiguredContextResolver sessionTargetConfiguredContextResolver)
        => configuredContextResolver = sessionTargetConfiguredContextResolver ?? throw new ArgumentNullException(nameof(sessionTargetConfiguredContextResolver));

    public async Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken)
    {
        var configured = await configuredContextResolver.ResolveConfiguredContextAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(configured) &&
            await SessionRuntimeInfrastructure.DockerContextExistsAsync(configured, cancellationToken).ConfigureAwait(false))
        {
            return ContextSelectionResult.FromContext(configured);
        }

        foreach (var candidate in SessionRuntimeConstants.ContextFallbackOrder)
        {
            if (await SessionRuntimeInfrastructure.DockerContextExistsAsync(candidate, cancellationToken).ConfigureAwait(false))
            {
                return ContextSelectionResult.FromContext(candidate);
            }
        }

        if (force)
        {
            return ContextSelectionResult.FromContext(DefaultContextName);
        }

        return ContextSelectionResult.FromError("No isolation context available. Run 'cai setup' or use --force.");
    }

    public async Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        var configured = await configuredContextResolver.ResolveConfiguredContextAsync(
            workspace ?? Directory.GetCurrentDirectory(),
            explicitConfig,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            contexts.Add(configured);
        }

        foreach (var fallback in SessionRuntimeConstants.ContextFallbackOrder)
        {
            if (!contexts.Contains(fallback, StringComparer.Ordinal) &&
                await SessionRuntimeInfrastructure.DockerContextExistsAsync(fallback, cancellationToken).ConfigureAwait(false))
            {
                contexts.Add(fallback);
            }
        }

        if (!contexts.Contains(DefaultContextName, StringComparer.Ordinal))
        {
            contexts.Add(DefaultContextName);
        }

        return contexts;
    }
}
