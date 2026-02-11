namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDataVolumeResolutionService
{
    private static async Task<string?> TryResolveGlobalVolumeAsync(string? configPath, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var globalResult = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, "agent.data_volume"),
            cancellationToken).ConfigureAwait(false);
        if (globalResult.ExitCode != 0)
        {
            return null;
        }

        var value = globalResult.StandardOutput.Trim();
        return IsValidVolume(value) ? value : null;
    }

    private static bool IsValidVolume(string? value)
        => !string.IsNullOrWhiteSpace(value) && SessionRuntimeInfrastructure.IsValidVolumeName(value);
}
