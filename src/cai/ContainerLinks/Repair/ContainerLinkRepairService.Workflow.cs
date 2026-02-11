namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairService
{
    private async Task<(bool Success, IReadOnlyList<ContainerLinkSpecEntry>? Entries)> LoadBuiltInSpecAsync(
        string containerName,
        CancellationToken cancellationToken)
    {
        var builtin = await specReader
            .ReadLinkSpecAsync(containerName, BuiltinSpecPath, required: true, cancellationToken)
            .ConfigureAwait(false);
        if (builtin.Error is not null)
        {
            await stderr.WriteLineAsync($"ERROR: {builtin.Error}").ConfigureAwait(false);
            return (false, null);
        }

        return (true, builtin.Entries);
    }

    private async Task<ContainerLinkSpecReadResult> LoadUserSpecAsync(
        string containerName,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var user = await specReader
            .ReadLinkSpecAsync(containerName, UserSpecPath, required: false, cancellationToken)
            .ConfigureAwait(false);
        if (user.Error is not null)
        {
            stats.Errors++;
            await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {user.Error}").ConfigureAwait(false);
        }

        return user;
    }

    private async Task TryUpdateCheckedTimestampAsync(
        string containerName,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        if (mode != ContainerLinkRepairMode.Fix || stats.Errors != 0)
        {
            return;
        }

        var timestampResult = await repairOperations
            .WriteCheckedTimestampAsync(containerName, CheckedAtFilePath, cancellationToken)
            .ConfigureAwait(false);
        if (!timestampResult.Success)
        {
            stats.Errors++;
            await stderr.WriteLineAsync($"[WARN] Failed to update links-checked-at timestamp: {timestampResult.Error}").ConfigureAwait(false);
            return;
        }

        await reporter.LogInfoAsync(quiet, "Updated links-checked-at timestamp").ConfigureAwait(false);
    }

    private static int ComputeExitCode(ContainerLinkRepairMode mode, ContainerLinkRepairStats stats)
    {
        if (stats.Errors > 0)
        {
            return 1;
        }

        if (mode == ContainerLinkRepairMode.Check && (stats.Broken + stats.Missing) > 0)
        {
            return 1;
        }

        return 0;
    }
}
