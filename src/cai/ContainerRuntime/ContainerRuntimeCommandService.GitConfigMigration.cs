using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeGitConfigService
{
    Task MigrateGitConfigAsync(string dataDir, bool quiet);

    Task SetupGitConfigAsync(string dataDir, string homeDir, bool quiet);
}

internal sealed partial class ContainerRuntimeGitConfigService : IContainerRuntimeGitConfigService
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeGitConfigService(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));
}
