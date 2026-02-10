namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorFixOperations
{
    private async Task<bool> TryWriteAvailableTargetsAsync(string? target, bool fixAll)
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
