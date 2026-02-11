using System.Text.Json;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host.RuntimeSupport.Paths;

internal static class CaiRuntimePathResolutionHelpers
{
    internal static bool IsExecutableOnPath(string fileName)
    {
        if (Path.IsPathRooted(fileName) && File.Exists(fileName))
        {
            return true;
        }

        var pathValue = System.Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return false;
        }

        var extensions = OperatingSystem.IsWindows()
            ? (System.Environment.GetEnvironmentVariable("PATHEXT")?.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
               ?? [".exe", ".cmd", ".bat"])
            : [string.Empty];

        foreach (var directory in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            foreach (var extension in extensions)
            {
                var candidate = Path.Combine(directory, $"{fileName}{extension}");
                if (File.Exists(candidate))
                {
                    return true;
                }
            }
        }

        return false;
    }

    internal static async Task<string> ResolveChannelAsync(IReadOnlyList<string> configFileNames, CancellationToken cancellationToken)
    {
        var envChannel = System.Environment.GetEnvironmentVariable("CAI_CHANNEL")
                         ?? System.Environment.GetEnvironmentVariable("CONTAINAI_CHANNEL");
        if (string.Equals(envChannel, "nightly", StringComparison.OrdinalIgnoreCase))
        {
            return "nightly";
        }

        if (string.Equals(envChannel, "stable", StringComparison.OrdinalIgnoreCase))
        {
            return "stable";
        }

        var configPath = CaiRuntimeConfigLocator.ResolveUserConfigPath(configFileNames);
        if (!File.Exists(configPath))
        {
            return "stable";
        }

        var result = await CaiRuntimeParseAndTimeHelpers
            .RunTomlAsync(() => TomlCommandProcessor.GetKey(configPath, "image.channel"), cancellationToken)
            .ConfigureAwait(false);

        if (result.ExitCode != 0)
        {
            return "stable";
        }

        return string.Equals(result.StandardOutput.Trim(), "nightly", StringComparison.OrdinalIgnoreCase)
            ? "nightly"
            : "stable";
    }

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

        var configPath = CaiRuntimeConfigLocator.ResolveConfigPath(workspace, configFileNames);
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
