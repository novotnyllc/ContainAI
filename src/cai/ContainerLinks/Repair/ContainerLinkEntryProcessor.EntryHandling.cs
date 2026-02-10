using System.ComponentModel;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkEntryProcessor
{
    private async Task ProcessEntryAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var state = await entryInspector.GetEntryStateAsync(containerName, entry, cancellationToken).ConfigureAwait(false);
        switch (state.Kind)
        {
            case EntryStateKind.Ok:
                stats.Ok++;
                return;
            case EntryStateKind.Missing:
                stats.Missing++;
                await reporter.LogInfoAsync(quiet, $"[MISSING] {entry.Link} -> {entry.Target}").ConfigureAwait(false);
                break;
            case EntryStateKind.DirectoryConflict when !entry.RemoveFirst:
                stats.Errors++;
                await standardError.WriteLineAsync($"[CONFLICT] {entry.Link} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
                return;
            case EntryStateKind.DirectoryConflict:
                stats.Broken++;
                await reporter.LogInfoAsync(quiet, $"[EXISTS_DIR] {entry.Link} is a directory (will remove with R flag)").ConfigureAwait(false);
                break;
            case EntryStateKind.FileConflict:
                stats.Broken++;
                await reporter.LogInfoAsync(quiet, $"[EXISTS_FILE] {entry.Link} is a regular file (will replace)").ConfigureAwait(false);
                break;
            case EntryStateKind.DanglingSymlink:
                stats.Broken++;
                await reporter.LogInfoAsync(quiet, $"[BROKEN] {entry.Link} -> {entry.Target} (dangling symlink)").ConfigureAwait(false);
                break;
            case EntryStateKind.WrongTarget:
                stats.Broken++;
                await reporter.LogInfoAsync(
                        quiet,
                        $"[WRONG_TARGET] {entry.Link} -> {state.CurrentTarget ?? "<unknown>"} (expected: {entry.Target})")
                    .ConfigureAwait(false);
                break;
            case EntryStateKind.Error:
                stats.Errors++;
                await standardError.WriteLineAsync($"[ERROR] {state.Error ?? "Unknown link inspection error"}").ConfigureAwait(false);
                return;
            default:
                throw new InvalidEnumArgumentException(nameof(state.Kind), (int)state.Kind, typeof(EntryStateKind));
        }

        if (mode == ContainerLinkRepairMode.Check)
        {
            return;
        }

        if (mode == ContainerLinkRepairMode.DryRun)
        {
            await reporter.LogInfoAsync(quiet, $"[WOULD] Create symlink: {entry.Link} -> {entry.Target}").ConfigureAwait(false);
            stats.Fixed++;
            return;
        }

        var repair = await repairOperations.RepairEntryAsync(containerName, entry, state, cancellationToken).ConfigureAwait(false);
        if (!repair.Success)
        {
            stats.Errors++;
            await standardError.WriteLineAsync($"ERROR: {repair.Error}").ConfigureAwait(false);
            return;
        }

        stats.Fixed++;
        await reporter.LogInfoAsync(quiet, $"[FIXED] {entry.Link} -> {entry.Target}").ConfigureAwait(false);
    }
}
