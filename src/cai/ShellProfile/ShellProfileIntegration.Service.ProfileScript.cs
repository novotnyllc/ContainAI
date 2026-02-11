namespace ContainAI.Cli.Host;

internal sealed partial class ShellProfileIntegrationService
{
    public async Task<bool> EnsureProfileScriptAsync(string homeDirectory, string binDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(binDirectory);

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(profileScriptPath)!);

        var script = scriptContentGenerator.BuildProfileScript(homeDirectory, binDirectory);
        if (File.Exists(profileScriptPath))
        {
            var existing = await File.ReadAllTextAsync(profileScriptPath, cancellationToken).ConfigureAwait(false);
            if (string.Equals(existing, script, StringComparison.Ordinal))
            {
                return false;
            }
        }

        await File.WriteAllTextAsync(profileScriptPath, script, cancellationToken).ConfigureAwait(false);
        return true;
    }
}
