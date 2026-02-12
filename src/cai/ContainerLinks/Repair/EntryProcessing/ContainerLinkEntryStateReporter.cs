using System.ComponentModel;

namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkEntryStateReporter(
    TextWriter standardError,
    IContainerLinkRepairReporter reporter) : IContainerLinkEntryStateReporter
{
    public async Task<bool> ReportAndDetermineRepairAsync(
        ContainerLinkSpecEntry entry,
        ContainerLinkEntryState state,
        bool quiet,
        ContainerLinkRepairStats stats)
    {
        ArgumentNullException.ThrowIfNull(stats);

        switch (state.Kind)
        {
            case EntryStateKind.Ok:
                stats.Ok++;
                return false;
            case EntryStateKind.Missing:
                stats.Missing++;
                await reporter.LogInfoAsync(quiet, $"[MISSING] {entry.Link} -> {entry.Target}").ConfigureAwait(false);
                return true;
            case EntryStateKind.DirectoryConflict when !entry.RemoveFirst:
                stats.Errors++;
                await standardError.WriteLineAsync($"[CONFLICT] {entry.Link} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
                return false;
            case EntryStateKind.DirectoryConflict:
                stats.Broken++;
                await reporter.LogInfoAsync(quiet, $"[EXISTS_DIR] {entry.Link} is a directory (will remove with R flag)").ConfigureAwait(false);
                return true;
            case EntryStateKind.FileConflict:
                stats.Broken++;
                await reporter.LogInfoAsync(quiet, $"[EXISTS_FILE] {entry.Link} is a regular file (will replace)").ConfigureAwait(false);
                return true;
            case EntryStateKind.DanglingSymlink:
                stats.Broken++;
                await reporter.LogInfoAsync(quiet, $"[BROKEN] {entry.Link} -> {entry.Target} (dangling symlink)").ConfigureAwait(false);
                return true;
            case EntryStateKind.WrongTarget:
                stats.Broken++;
                await reporter.LogInfoAsync(
                        quiet,
                        $"[WRONG_TARGET] {entry.Link} -> {state.CurrentTarget ?? "<unknown>"} (expected: {entry.Target})")
                    .ConfigureAwait(false);
                return true;
            case EntryStateKind.Error:
                stats.Errors++;
                await standardError.WriteLineAsync($"[ERROR] {state.Error ?? "Unknown link inspection error"}").ConfigureAwait(false);
                return false;
            default:
                throw new InvalidEnumArgumentException(nameof(state.Kind), (int)state.Kind, typeof(EntryStateKind));
        }
    }
}
