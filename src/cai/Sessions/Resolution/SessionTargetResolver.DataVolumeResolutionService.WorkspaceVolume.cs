namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDataVolumeResolutionService
{
    private async Task<string?> TryResolveWorkspaceVolumeAsync(string? configPath, string workspace, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var workspaceResult = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceResult.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceResult.StandardOutput))
        {
            return null;
        }

        var value = parsingValidationService.TryReadWorkspaceStringProperty(workspaceResult.StandardOutput, "data_volume");
        return IsValidVolume(value) ? value : null;
    }
}
