using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeInitCommandHandler : IContainerRuntimeInitCommandHandler
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeInitializationWorkflow workflow;

    public ContainerRuntimeInitCommandHandler(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeInitializationWorkflow workflow)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.workflow = workflow ?? throw new ArgumentNullException(nameof(workflow));
    }

    public async Task<int> HandleAsync(InitCommandParsing options, CancellationToken cancellationToken)
    {
        try
        {
            await workflow.RunAsync(options, cancellationToken).ConfigureAwait(false);
            return 0;
        }
        catch (Exception ex) when (ContainerRuntimeExceptionHandling.IsHandled(ex))
        {
            await context.StandardError.WriteLineAsync($"[ERROR] {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }
}
