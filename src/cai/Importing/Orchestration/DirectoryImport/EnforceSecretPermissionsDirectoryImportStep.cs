namespace ContainAI.Cli.Host;

internal sealed class EnforceSecretPermissionsDirectoryImportStep : IDirectoryImportStep
{
    private readonly ImportDirectorySecretPermissionsEnforcer secretPermissionsEnforcer;

    public EnforceSecretPermissionsDirectoryImportStep(ImportDirectorySecretPermissionsEnforcer importDirectorySecretPermissionsEnforcer)
        => secretPermissionsEnforcer = importDirectorySecretPermissionsEnforcer ?? throw new ArgumentNullException(nameof(importDirectorySecretPermissionsEnforcer));

    public Task<int> ExecuteAsync(DirectoryImportContext context, CancellationToken cancellationToken)
        => secretPermissionsEnforcer.EnforceIfNeededAsync(
            context.Options,
            context.Volume,
            context.ManifestEntries,
            cancellationToken);
}
