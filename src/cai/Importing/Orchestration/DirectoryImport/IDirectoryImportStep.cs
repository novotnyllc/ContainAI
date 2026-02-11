namespace ContainAI.Cli.Host;

internal interface IDirectoryImportStep
{
    Task<int> ExecuteAsync(DirectoryImportContext context, CancellationToken cancellationToken);
}
