using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed class ContainerRuntimeManifestBootstrapService : IContainerRuntimeManifestBootstrapService
{
    private readonly IContainerRuntimeVolumeBootstrapper volumeBootstrapper;
    private readonly IContainerRuntimeUserManifestProcessor userManifestProcessor;
    private readonly IContainerRuntimeHookRunner hookRunner;

    public ContainerRuntimeManifestBootstrapService(IContainerRuntimeExecutionContext context)
        : this(
            new ContainerRuntimeVolumeBootstrapper(
                context ?? throw new ArgumentNullException(nameof(context)),
                new ManifestApplier(context.ManifestTomlParser)),
            new ContainerRuntimeUserManifestProcessor(
                context,
                new ManifestApplier(context.ManifestTomlParser)),
            new ContainerRuntimeHookRunner(context))
    {
    }

    internal ContainerRuntimeManifestBootstrapService(
        IContainerRuntimeVolumeBootstrapper volumeBootstrapper,
        IContainerRuntimeUserManifestProcessor userManifestProcessor,
        IContainerRuntimeHookRunner hookRunner)
    {
        this.volumeBootstrapper = volumeBootstrapper ?? throw new ArgumentNullException(nameof(volumeBootstrapper));
        this.userManifestProcessor = userManifestProcessor ?? throw new ArgumentNullException(nameof(userManifestProcessor));
        this.hookRunner = hookRunner ?? throw new ArgumentNullException(nameof(hookRunner));
    }

    public Task EnsureVolumeStructureAsync(string dataDir, string manifestsDir, bool quiet)
        => volumeBootstrapper.EnsureVolumeStructureAsync(dataDir, manifestsDir, quiet);

    public Task ProcessUserManifestsAsync(string dataDir, string homeDir, bool quiet)
        => userManifestProcessor.ProcessUserManifestsAsync(dataDir, homeDir, quiet);

    public Task RunHooksAsync(
        string hooksDirectory,
        string workspaceDirectory,
        string homeDirectory,
        bool quiet,
        CancellationToken cancellationToken)
        => hookRunner.RunHooksAsync(hooksDirectory, workspaceDirectory, homeDirectory, quiet, cancellationToken);
}
