namespace ContainAI.Cli.Host;

internal interface IImportPostCopyOperations
{
    Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ApplyManifestPostCopyRulesAsync(
        string volume,
        ManifestEntry entry,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}

internal sealed class CaiImportPostCopyOperations : CaiRuntimeSupport
    , IImportPostCopyOperations
{
    private readonly IImportSecretPermissionOperations secretPermissionOperations;
    private readonly IImportGitConfigFilterOperations gitConfigFilterOperations;

    public CaiImportPostCopyOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportSecretPermissionOperations(standardOutput, standardError),
            new ImportGitConfigFilterOperations(standardOutput, standardError))
    {
    }

    internal CaiImportPostCopyOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportSecretPermissionOperations importSecretPermissionOperations,
        IImportGitConfigFilterOperations importGitConfigFilterOperations)
        : base(standardOutput, standardError)
        => (secretPermissionOperations, gitConfigFilterOperations) = (
            importSecretPermissionOperations ?? throw new ArgumentNullException(nameof(importSecretPermissionOperations)),
            importGitConfigFilterOperations ?? throw new ArgumentNullException(nameof(importGitConfigFilterOperations)));

    public Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
        => secretPermissionOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);

    public async Task<int> ApplyManifestPostCopyRulesAsync(
        string volume,
        ManifestEntry entry,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            return 0;
        }

        var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
        if (entry.Flags.Contains('g', StringComparison.Ordinal))
        {
            var gitFilterCode = await gitConfigFilterOperations.ApplyGitConfigFilterAsync(
                volume,
                normalizedTarget,
                verbose,
                cancellationToken).ConfigureAwait(false);
            if (gitFilterCode != 0)
            {
                return gitFilterCode;
            }
        }

        if (!entry.Flags.Contains('s', StringComparison.Ordinal))
        {
            return 0;
        }

        return await secretPermissionOperations.ApplyEntrySecretPermissionsAsync(
            volume,
            normalizedTarget,
            entry.Flags.Contains('d', StringComparison.Ordinal),
            cancellationToken).ConfigureAwait(false);
    }
}
