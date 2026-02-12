namespace ContainAI.Cli.Host;

internal sealed class CaiDoctorFixTemplateRunner : ICaiDoctorFixTemplateRunner
{
    private readonly CaiTemplateRestoreOperations templateRestoreOperations;

    public CaiDoctorFixTemplateRunner(CaiTemplateRestoreOperations caiTemplateRestoreOperations)
        => templateRestoreOperations = caiTemplateRestoreOperations ?? throw new ArgumentNullException(nameof(caiTemplateRestoreOperations));

    public Task<int> RunAsync(bool fixAll, string? target, string? targetArg, CancellationToken cancellationToken)
    {
        if (!fixAll && !string.Equals(target, "template", StringComparison.Ordinal))
        {
            return Task.FromResult(0);
        }

        return templateRestoreOperations.RestoreTemplatesAsync(
            targetArg,
            includeAll: fixAll || string.Equals(targetArg, "--all", StringComparison.Ordinal),
            cancellationToken);
    }
}
