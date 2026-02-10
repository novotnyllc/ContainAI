namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorFixOperations
{
    private async Task<int> RunTemplateFixAsync(
        bool fixAll,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
        if (!fixAll && !string.Equals(target, "template", StringComparison.Ordinal))
        {
            return 0;
        }

        return await templateRestoreOperations
            .RestoreTemplatesAsync(
                targetArg,
                includeAll: fixAll || string.Equals(targetArg, "--all", StringComparison.Ordinal),
                cancellationToken)
            .ConfigureAwait(false);
    }
}
