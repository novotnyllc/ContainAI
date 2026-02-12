namespace ContainAI.Cli.Host;

internal sealed record ContainerLinkSpecSetLoadResult(
    bool Success,
    IReadOnlyList<ContainerLinkSpecEntry> BuiltinEntries,
    IReadOnlyList<ContainerLinkSpecEntry> UserEntries)
{
    public static readonly ContainerLinkSpecSetLoadResult Failed = new(false, [], []);
}

internal sealed class ContainerLinkSpecSetLoader : IContainerLinkSpecSetLoader
{
    private readonly IContainerLinkSpecReader specReader;
    private readonly TextWriter standardError;

    public ContainerLinkSpecSetLoader(IContainerLinkSpecReader specReader, TextWriter standardError)
    {
        this.specReader = specReader ?? throw new ArgumentNullException(nameof(specReader));
        this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<ContainerLinkSpecSetLoadResult> LoadAsync(
        string containerName,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(containerName);
        ArgumentNullException.ThrowIfNull(stats);

        var builtin = await specReader
            .ReadLinkSpecAsync(containerName, ContainerLinkRepairFilePaths.BuiltinSpecPath, required: true, cancellationToken)
            .ConfigureAwait(false);
        if (builtin.Error is not null)
        {
            await standardError.WriteLineAsync($"ERROR: {builtin.Error}").ConfigureAwait(false);
            return ContainerLinkSpecSetLoadResult.Failed;
        }

        var user = await specReader
            .ReadLinkSpecAsync(containerName, ContainerLinkRepairFilePaths.UserSpecPath, required: false, cancellationToken)
            .ConfigureAwait(false);
        if (user.Error is not null)
        {
            stats.Errors++;
            await standardError.WriteLineAsync($"[WARN] Failed to process user link spec: {user.Error}").ConfigureAwait(false);
        }

        return new ContainerLinkSpecSetLoadResult(
            Success: true,
            BuiltinEntries: builtin.Entries,
            UserEntries: user.Entries);
    }
}
