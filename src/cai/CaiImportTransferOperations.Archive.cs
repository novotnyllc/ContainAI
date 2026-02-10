namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportTransferOperations
{
    public Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken)
        => archiveTransferOperations.RestoreArchiveImportAsync(volume, archivePath, excludePriv, cancellationToken);
}
