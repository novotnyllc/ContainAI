namespace ContainAI.Cli.Host;

internal interface IShellProfileScriptFileOperations
{
    Task<bool> EnsureProfileScriptAsync(string profileScriptPath, string script, CancellationToken cancellationToken);

    Task<bool> RemoveProfileScriptAsync(string profileDirectoryPath, string profileScriptPath, CancellationToken cancellationToken);
}
