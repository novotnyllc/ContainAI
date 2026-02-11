using System.Text.Json;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host.RuntimeSupport.Paths;

internal static partial class CaiRuntimePathResolutionHelpers
{
    internal static async Task<string?> ResolveDataVolumeAsync(
        string workspace,
        string? explicitVolume,
        IReadOnlyList<string> configFileNames,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            return explicitVolume;
        }

        var envVolume = System.Environment.GetEnvironmentVariable("CONTAINAI_DATA_VOLUME");
        if (!string.IsNullOrWhiteSpace(envVolume))
        {
            return envVolume;
        }

        var configPath = CaiRuntimeConfigPathHelpers.ResolveConfigPath(workspace, configFileNames);
        if (!File.Exists(configPath))
        {
            return "containai-data";
        }

        var normalizedWorkspace = CaiRuntimeWorkspacePathHelpers.CanonicalizeWorkspacePath(workspace);
        var workspaceState = await CaiRuntimeParseAndTimeHelpers
            .RunTomlAsync(() => TomlCommandProcessor.GetWorkspace(configPath, normalizedWorkspace), cancellationToken)
            .ConfigureAwait(false);

        if (workspaceState.ExitCode == 0 && !string.IsNullOrWhiteSpace(workspaceState.StandardOutput))
        {
            using var json = JsonDocument.Parse(workspaceState.StandardOutput);
            if (json.RootElement.ValueKind == JsonValueKind.Object &&
                json.RootElement.TryGetProperty("data_volume", out var workspaceVolume))
            {
                var volume = workspaceVolume.GetString();
                if (!string.IsNullOrWhiteSpace(volume))
                {
                    return volume;
                }
            }
        }

        var globalResult = await CaiRuntimeParseAndTimeHelpers
            .RunTomlAsync(() => TomlCommandProcessor.GetKey(configPath, "agent.data_volume"), cancellationToken)
            .ConfigureAwait(false);

        if (globalResult.ExitCode == 0)
        {
            var volume = globalResult.StandardOutput.Trim();
            if (!string.IsNullOrWhiteSpace(volume))
            {
                return volume;
            }
        }

        return "containai-data";
    }
}
