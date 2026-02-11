namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestTransferOperations : IImportManifestTransferOperations
{
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportManifestTargetInitializationOperations targetInitializationOperations;
    private readonly IImportManifestEntryTransferPipeline manifestEntryTransferPipeline;

    public ImportManifestTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(ImportManifestTransferDependencyFactory.Create(standardOutput, standardError))
    {
    }

    internal ImportManifestTransferOperations(ImportManifestTransferDependencies dependencies)
    {
        ArgumentNullException.ThrowIfNull(dependencies);
        postCopyOperations = dependencies.PostCopyOperations;
        targetInitializationOperations = dependencies.TargetInitializationOperations;
        manifestEntryTransferPipeline = dependencies.ManifestEntryTransferPipeline;
    }

    public async Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
        => await targetInitializationOperations.InitializeTargetsAsync(
            volume,
            sourceRoot,
            entries,
            noSecrets,
            cancellationToken).ConfigureAwait(false);

    public async Task<int> ImportManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => await manifestEntryTransferPipeline.ImportAsync(
            volume,
            sourceRoot,
            entry,
            excludePriv,
            noExcludes,
            dryRun,
            verbose,
            cancellationToken).ConfigureAwait(false);

    public Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
        => postCopyOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);
}
