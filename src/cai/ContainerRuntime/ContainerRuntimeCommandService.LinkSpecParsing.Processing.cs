using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed partial class ContainerRuntimeLinkSpecProcessor
{
    public async Task ProcessLinkSpecAsync(
        string specPath,
        LinkRepairMode mode,
        bool quiet,
        string specName,
        LinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var json = await linkSpecFileReader.ReadAllTextAsync(specPath, cancellationToken).ConfigureAwait(false);
        var entries = linkSpecParser.ParseEntries(specPath, json);

        await context.LogInfoAsync(quiet, $"Processing {specName} ({entries.Count} links)").ConfigureAwait(false);

        foreach (var entry in entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!linkSpecEntryValidator.TryValidate(entry, out var validatedEntry))
            {
                stats.Errors++;
                await context.StandardError.WriteLineAsync($"[WARN] Skipping invalid link spec entry in {specPath}").ConfigureAwait(false);
                continue;
            }

            await ProcessValidatedEntryAsync(validatedEntry, mode, quiet, stats).ConfigureAwait(false);
        }
    }
}
