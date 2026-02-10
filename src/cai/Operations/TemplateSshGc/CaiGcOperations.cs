namespace ContainAI.Cli.Host;

internal sealed partial class CaiGcOperations : CaiRuntimeSupport
{
    private readonly IReadOnlyList<string> containAiImagePrefixes;

    public CaiGcOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IReadOnlyList<string> containAiImagePrefixes)
        : base(standardOutput, standardError)
        => this.containAiImagePrefixes = containAiImagePrefixes ?? throw new ArgumentNullException(nameof(containAiImagePrefixes));

    public async Task<int> RunGcAsync(
        bool dryRun,
        bool force,
        bool includeImages,
        string ageValue,
        CancellationToken cancellationToken)
    {
        if (!TryParseAgeDuration(ageValue, out var minimumAge))
        {
            await stderr.WriteLineAsync($"Invalid --age value: {ageValue}").ConfigureAwait(false);
            return 1;
        }

        var candidates = await CollectContainerPruneCandidatesAsync(minimumAge, cancellationToken).ConfigureAwait(false);
        if (candidates.ExitCode != 0)
        {
            return candidates.ExitCode;
        }

        if (!await ConfirmContainerPruneAsync(dryRun, force, candidates.PruneCandidates.Count).ConfigureAwait(false))
        {
            return 1;
        }

        var failures = candidates.Failures + await PruneContainersAsync(candidates.PruneCandidates, dryRun, cancellationToken).ConfigureAwait(false);

        if (includeImages)
        {
            if (!dryRun && !force)
            {
                await stderr.WriteLineAsync("Use --force with --images to remove images.").ConfigureAwait(false);
                return 1;
            }

            failures += await PruneImagesAsync(dryRun, cancellationToken).ConfigureAwait(false);
        }

        return failures == 0 ? 0 : 1;
    }
}
