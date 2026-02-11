namespace ContainAI.Cli.Host;

internal sealed partial class ShellProfileIntegrationService
{
    public Task<bool> RemoveProfileScriptAsync(string homeDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        cancellationToken.ThrowIfCancellationRequested();

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        if (!File.Exists(profileScriptPath))
        {
            return Task.FromResult(false);
        }

        File.Delete(profileScriptPath);

        var profileDirectory = GetProfileDirectoryPath(homeDirectory);
        if (Directory.Exists(profileDirectory) && !Directory.EnumerateFileSystemEntries(profileDirectory).Any())
        {
            Directory.Delete(profileDirectory);
        }

        return Task.FromResult(true);
    }
}
