namespace ContainAI.Cli.Host;

internal sealed class ShellProfileScriptFileOperations : IShellProfileScriptFileOperations
{
    private readonly IShellProfileFileSystem fileSystem;

    public ShellProfileScriptFileOperations(IShellProfileFileSystem fileSystem)
        => this.fileSystem = fileSystem ?? throw new ArgumentNullException(nameof(fileSystem));

    public async Task<bool> EnsureProfileScriptAsync(string profileScriptPath, string script, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(profileScriptPath);
        ArgumentNullException.ThrowIfNull(script);

        fileSystem.CreateDirectory(Path.GetDirectoryName(profileScriptPath)!);

        if (fileSystem.FileExists(profileScriptPath))
        {
            var existing = await fileSystem.ReadAllTextAsync(profileScriptPath, cancellationToken).ConfigureAwait(false);
            if (string.Equals(existing, script, StringComparison.Ordinal))
            {
                return false;
            }
        }

        await fileSystem.WriteAllTextAsync(profileScriptPath, script, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public Task<bool> RemoveProfileScriptAsync(string profileDirectoryPath, string profileScriptPath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(profileDirectoryPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(profileScriptPath);
        cancellationToken.ThrowIfCancellationRequested();

        if (!fileSystem.FileExists(profileScriptPath))
        {
            return Task.FromResult(false);
        }

        fileSystem.DeleteFile(profileScriptPath);
        if (fileSystem.DirectoryExists(profileDirectoryPath) && !fileSystem.EnumerateFileSystemEntries(profileDirectoryPath).Any())
        {
            fileSystem.DeleteDirectory(profileDirectoryPath);
        }

        return Task.FromResult(true);
    }
}
