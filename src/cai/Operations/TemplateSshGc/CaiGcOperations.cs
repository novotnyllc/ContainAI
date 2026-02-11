namespace ContainAI.Cli.Host;

internal sealed class CaiGcOperations
{
    private readonly TextWriter stderr;
    private readonly ICaiGcAgeParser ageParser;
    private readonly ICaiGcCandidateCollector candidateCollector;
    private readonly ICaiGcConfirmationPrompt confirmationPrompt;
    private readonly ICaiGcContainerPruner containerPruner;
    private readonly ICaiGcImagePruner imagePruner;

    public CaiGcOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ICaiGcAgeParser caiGcAgeParser,
        ICaiGcCandidateCollector caiGcCandidateCollector,
        ICaiGcConfirmationPrompt caiGcConfirmationPrompt,
        ICaiGcContainerPruner caiGcContainerPruner,
        ICaiGcImagePruner caiGcImagePruner)
    {
        _ = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        ageParser = caiGcAgeParser ?? throw new ArgumentNullException(nameof(caiGcAgeParser));
        candidateCollector = caiGcCandidateCollector ?? throw new ArgumentNullException(nameof(caiGcCandidateCollector));
        confirmationPrompt = caiGcConfirmationPrompt ?? throw new ArgumentNullException(nameof(caiGcConfirmationPrompt));
        containerPruner = caiGcContainerPruner ?? throw new ArgumentNullException(nameof(caiGcContainerPruner));
        imagePruner = caiGcImagePruner ?? throw new ArgumentNullException(nameof(caiGcImagePruner));
    }

    public async Task<int> RunGcAsync(
        bool dryRun,
        bool force,
        bool includeImages,
        string ageValue,
        CancellationToken cancellationToken)
    {
        if (!ageParser.TryParseMinimumAge(ageValue, out var minimumAge))
        {
            await stderr.WriteLineAsync($"Invalid --age value: {ageValue}").ConfigureAwait(false);
            return 1;
        }

        var candidates = await candidateCollector.CollectAsync(minimumAge, cancellationToken).ConfigureAwait(false);
        if (candidates.ExitCode != 0)
        {
            return candidates.ExitCode;
        }

        if (!await confirmationPrompt.ConfirmAsync(dryRun, force, candidates.PruneCandidates.Count).ConfigureAwait(false))
        {
            return 1;
        }

        var failures = candidates.Failures + await containerPruner.PruneAsync(candidates.PruneCandidates, dryRun, cancellationToken).ConfigureAwait(false);

        if (includeImages)
        {
            if (!dryRun && !force)
            {
                await stderr.WriteLineAsync("Use --force with --images to remove images.").ConfigureAwait(false);
                return 1;
            }

            failures += await imagePruner.PruneAsync(dryRun, cancellationToken).ConfigureAwait(false);
        }

        return failures == 0 ? 0 : 1;
    }
}
