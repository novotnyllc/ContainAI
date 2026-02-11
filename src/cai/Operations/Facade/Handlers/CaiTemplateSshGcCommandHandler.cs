using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiTemplateSshGcCommandHandler
{
    private readonly CaiTemplateSshAndGcOperations templateSshAndGcOperations;

    public CaiTemplateSshGcCommandHandler(CaiTemplateSshAndGcOperations caiTemplateSshAndGcOperations)
        => templateSshAndGcOperations = caiTemplateSshAndGcOperations ?? throw new ArgumentNullException(nameof(caiTemplateSshAndGcOperations));

    public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return templateSshAndGcOperations.RunStopAsync(
            containerName: options.Container,
            stopAll: options.All,
            remove: options.Remove,
            force: options.Force,
            exportFirst: options.Export,
            cancellationToken);
    }

    public Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return templateSshAndGcOperations.RunGcAsync(
            dryRun: options.DryRun,
            force: options.Force,
            includeImages: options.Images,
            ageValue: options.Age ?? "30d",
            cancellationToken);
    }

    public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return templateSshAndGcOperations.RunSshCleanupAsync(options.DryRun, cancellationToken);
    }

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return templateSshAndGcOperations.RunTemplateUpgradeAsync(options.Name, options.DryRun, cancellationToken);
    }
}
