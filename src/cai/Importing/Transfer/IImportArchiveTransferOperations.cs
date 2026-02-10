namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportArchiveTransferOperations
{
    Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken);
}
