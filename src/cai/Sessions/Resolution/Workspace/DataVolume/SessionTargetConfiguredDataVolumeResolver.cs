using ContainAI.Cli.Host;
using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace.DataVolume;

internal interface ISessionTargetConfiguredDataVolumeResolver
{
    Task<string?> ResolveConfiguredDataVolumeAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken);
}

internal sealed class SessionTargetConfiguredDataVolumeResolver(
    ISessionTargetParsingValidationService parsingValidationService,
    ISessionRuntimeOperations runtimeOperations) : ISessionTargetConfiguredDataVolumeResolver
{
    public async Task<string?> ResolveConfiguredDataVolumeAsync(
        string workspace,
        string? explicitConfig,
        CancellationToken cancellationToken)
    {
        var userConfigVolume = await TryResolveWorkspaceVolumeAsync(
            runtimeOperations.ResolveUserConfigPath(),
            workspace,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(userConfigVolume))
        {
            return userConfigVolume;
        }

        var discoveredConfig = runtimeOperations.FindConfigFile(workspace, explicitConfig);
        var workspaceVolume = await TryResolveWorkspaceVolumeAsync(discoveredConfig, workspace, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(workspaceVolume))
        {
            return workspaceVolume;
        }

        return await TryResolveGlobalVolumeAsync(discoveredConfig, cancellationToken).ConfigureAwait(false);
    }

    private async Task<string?> TryResolveGlobalVolumeAsync(string? configPath, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var globalResult = await runtimeOperations.RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, "agent.data_volume"),
            cancellationToken).ConfigureAwait(false);
        if (globalResult.ExitCode != 0)
        {
            return null;
        }

        var value = globalResult.StandardOutput.Trim();
        return IsValidVolume(value) ? value : null;
    }

    private async Task<string?> TryResolveWorkspaceVolumeAsync(string? configPath, string workspace, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var workspaceResult = await runtimeOperations.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceResult.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceResult.StandardOutput))
        {
            return null;
        }

        var value = parsingValidationService.TryReadWorkspaceStringProperty(workspaceResult.StandardOutput, "data_volume");
        return IsValidVolume(value) ? value : null;
    }

    private bool IsValidVolume(string? value)
        => !string.IsNullOrWhiteSpace(value) && runtimeOperations.IsValidVolumeName(value);
}
