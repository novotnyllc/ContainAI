using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeManifestBootstrapService
{
    Task EnsureVolumeStructureAsync(string dataDir, string manifestsDir, bool quiet);

    Task ProcessUserManifestsAsync(string dataDir, string homeDir, bool quiet);

    Task RunHooksAsync(string hooksDirectory, string workspaceDirectory, string homeDirectory, bool quiet, CancellationToken cancellationToken);
}

internal sealed partial class ContainerRuntimeManifestBootstrapService : IContainerRuntimeManifestBootstrapService
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IManifestApplier manifestApplier;

    public ContainerRuntimeManifestBootstrapService(IContainerRuntimeExecutionContext context)
        : this(context, new ManifestApplier(context?.ManifestTomlParser ?? throw new ArgumentNullException(nameof(context))))
    {
    }

    internal ContainerRuntimeManifestBootstrapService(
        IContainerRuntimeExecutionContext context,
        IManifestApplier manifestApplier)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.manifestApplier = manifestApplier ?? throw new ArgumentNullException(nameof(manifestApplier));
    }

}
