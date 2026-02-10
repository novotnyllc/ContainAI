namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportPathOperations
{
    public async Task<bool> ResolveImportExcludePrivAsync(string workspace, string? explicitConfigPath, CancellationToken cancellationToken)
    {
        var configPath = ResolveImportConfigPath(workspace, explicitConfigPath);
        if (!File.Exists(configPath))
        {
            return true;
        }

        var result = await RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, importExcludePrivKey),
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return true;
        }

        return !bool.TryParse(result.StandardOutput.Trim(), out var parsed) || parsed;
    }

    private static string ResolveImportConfigPath(string workspace, string? explicitConfigPath)
        => !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath!
            : ResolveConfigPath(workspace);
}
