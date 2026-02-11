namespace ContainAI.Cli.Host;

internal interface ICaiDoctorFixTargetOperations
{
    Task<bool> TryWriteAvailableTargetsAsync(string? target, bool fixAll);
}

internal sealed class CaiDoctorFixTargetOperations : ICaiDoctorFixTargetOperations
{
    private readonly TextWriter stdout;

    public CaiDoctorFixTargetOperations(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task<bool> TryWriteAvailableTargetsAsync(string? target, bool fixAll)
    {
        if (target is not null || fixAll)
        {
            return false;
        }

        await stdout.WriteLineAsync("Available doctor fix targets:").ConfigureAwait(false);
        await stdout.WriteLineAsync("  --all").ConfigureAwait(false);
        await stdout.WriteLineAsync("  container [--all|<name>]").ConfigureAwait(false);
        await stdout.WriteLineAsync("  template [--all|<name>]").ConfigureAwait(false);
        return true;
    }
}
