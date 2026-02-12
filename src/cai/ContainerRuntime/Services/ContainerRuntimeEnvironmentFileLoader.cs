using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed class ContainerRuntimeEnvironmentFileLoader : IContainerRuntimeEnvironmentFileLoader
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeEnvironmentFileReadinessService readinessService;
    private readonly IContainerRuntimeEnvironmentLineApplier lineApplier;

    public ContainerRuntimeEnvironmentFileLoader(IContainerRuntimeExecutionContext context)
        : this(
            context,
            new ContainerRuntimeEnvironmentFileReadinessService(context),
            new ContainerRuntimeEnvironmentLineApplier(context))
    {
    }

    internal ContainerRuntimeEnvironmentFileLoader(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeEnvironmentFileReadinessService readinessService,
        IContainerRuntimeEnvironmentLineApplier lineApplier)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.readinessService = readinessService ?? throw new ArgumentNullException(nameof(readinessService));
        this.lineApplier = lineApplier ?? throw new ArgumentNullException(nameof(lineApplier));
    }

    public async Task LoadEnvFileAsync(string envFilePath, bool quiet)
    {
        if (!await readinessService.CanLoadAsync(envFilePath).ConfigureAwait(false))
        {
            return;
        }

        await context.LogInfoAsync(quiet, "Loading environment from .env").ConfigureAwait(false);

        var lines = await File.ReadAllLinesAsync(envFilePath).ConfigureAwait(false);
        for (var index = 0; index < lines.Length; index++)
        {
            await lineApplier.ApplyLineIfValidAsync(lines[index], index + 1).ConfigureAwait(false);
        }
    }
}
