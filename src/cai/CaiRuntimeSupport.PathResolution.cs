using System.Text.Json;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static bool IsExecutableOnPath(string fileName)
    {
        if (Path.IsPathRooted(fileName) && File.Exists(fileName))
        {
            return true;
        }

        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return false;
        }

        var extensions = OperatingSystem.IsWindows()
            ? (Environment.GetEnvironmentVariable("PATHEXT")?.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
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

    protected static string ResolveHomeDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("HOME");
        }

        return string.IsNullOrWhiteSpace(home) ? Directory.GetCurrentDirectory() : home;
    }

    protected static string ExpandHomePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return path;
        }

        if (!path.StartsWith('~'))
        {
            return path;
        }

        var home = ResolveHomeDirectory();
        if (path.Length == 1)
        {
            return home;
        }

        return path[1] switch
        {
            '/' or '\\' => Path.Combine(home, path[2..]),
            _ => path,
        };
    }

    protected static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    protected static string ResolveUserConfigPath()
    {
        var home = ResolveHomeDirectory();
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai", ConfigFileNames[0]);
    }

    protected static string? TryFindExistingUserConfigPath()
    {
        var home = ResolveHomeDirectory();
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;
        var containAiConfigDirectory = Path.Combine(configRoot, "containai");
        foreach (var fileName in ConfigFileNames)
        {
            var candidate = Path.Combine(containAiConfigDirectory, fileName);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    protected static string ResolveConfigPath(string? workspacePath)
    {
        var explicitConfigPath = Environment.GetEnvironmentVariable("CONTAINAI_CONFIG");
        if (!string.IsNullOrWhiteSpace(explicitConfigPath))
        {
            return Path.GetFullPath(ExpandHomePath(explicitConfigPath));
        }

        var workspaceConfigPath = TryFindWorkspaceConfigPath(workspacePath);
        if (!string.IsNullOrWhiteSpace(workspaceConfigPath))
        {
            return workspaceConfigPath;
        }

        var userConfigPath = TryFindExistingUserConfigPath();
        return userConfigPath ?? ResolveUserConfigPath();
    }

    protected static string? TryFindWorkspaceConfigPath(string? workspacePath)
    {
        var startPath = string.IsNullOrWhiteSpace(workspacePath)
            ? Directory.GetCurrentDirectory()
            : ExpandHomePath(workspacePath);

        var normalizedStart = Path.GetFullPath(startPath);
        var current = File.Exists(normalizedStart)
            ? Path.GetDirectoryName(normalizedStart)
            : normalizedStart;

        while (!string.IsNullOrWhiteSpace(current))
        {
            foreach (var fileName in ConfigFileNames)
            {
                var candidate = Path.Combine(current, ".containai", fileName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }

            var parent = Directory.GetParent(current);
            if (parent is null || string.Equals(parent.FullName, current, StringComparison.Ordinal))
            {
                break;
            }

            current = parent.FullName;
        }

        return null;
    }

    protected static string ResolveTemplatesDirectory()
    {
        var home = ResolveHomeDirectory();
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai", "templates");
    }

    protected static async Task<string> ResolveChannelAsync(CancellationToken cancellationToken)
    {
        var envChannel = Environment.GetEnvironmentVariable("CAI_CHANNEL")
                         ?? Environment.GetEnvironmentVariable("CONTAINAI_CHANNEL");
        if (string.Equals(envChannel, "nightly", StringComparison.OrdinalIgnoreCase))
        {
            return "nightly";
        }

        if (string.Equals(envChannel, "stable", StringComparison.OrdinalIgnoreCase))
        {
            return "stable";
        }

        var configPath = ResolveUserConfigPath();
        if (!File.Exists(configPath))
        {
            return "stable";
        }

        var result = await RunTomlAsync(() => TomlCommandProcessor.GetKey(configPath, "image.channel"), cancellationToken).ConfigureAwait(false);

        if (result.ExitCode != 0)
        {
            return "stable";
        }

        return string.Equals(result.StandardOutput.Trim(), "nightly", StringComparison.OrdinalIgnoreCase)
            ? "nightly"
            : "stable";
    }

    protected static async Task<string?> ResolveDataVolumeAsync(string workspace, string? explicitVolume, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            return explicitVolume;
        }

        var envVolume = Environment.GetEnvironmentVariable("CONTAINAI_DATA_VOLUME");
        if (!string.IsNullOrWhiteSpace(envVolume))
        {
            return envVolume;
        }

        var configPath = ResolveConfigPath(workspace);
        if (!File.Exists(configPath))
        {
            return "containai-data";
        }

        var normalizedWorkspace = Path.GetFullPath(ExpandHomePath(workspace));
        var workspaceState = await RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, normalizedWorkspace),
            cancellationToken).ConfigureAwait(false);

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

        var globalResult = await RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, "agent.data_volume"),
            cancellationToken).ConfigureAwait(false);

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
