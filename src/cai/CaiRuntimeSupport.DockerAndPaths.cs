using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static async Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
    {
        var result = await DockerRunAsync(["inspect", "--type", "container", containerName], cancellationToken).ConfigureAwait(false);
        return result == 0;
    }

    protected static async Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        return result.ExitCode;
    }

    protected static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = new List<string>();
        if (!string.IsNullOrWhiteSpace(context))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return await RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    protected static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, string standardInput, CancellationToken cancellationToken)
    {
        var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = new List<string>();
        if (!string.IsNullOrWhiteSpace(context))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return await RunProcessCaptureAsync("docker", dockerArgs, cancellationToken, standardInput).ConfigureAwait(false);
    }

    protected static async Task<CommandExecutionResult> ExecuteDockerCommandAsync(
        IReadOnlyList<string> args,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        var result = standardInput is null
            ? await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false)
            : await DockerCaptureAsync(args, standardInput, cancellationToken).ConfigureAwait(false);
        return new CommandExecutionResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    protected static async Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
    {
        foreach (var contextName in new[] { "containai-docker", "containai-secure", "docker-containai" })
        {
            var probe = await RunProcessCaptureAsync(
                "docker",
                ["context", "inspect", contextName],
                cancellationToken).ConfigureAwait(false);
            if (probe.ExitCode == 0)
            {
                return contextName;
            }
        }

        return null;
    }

    protected static async Task<List<string>> FindContainerContextsAsync(string containerName, CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        foreach (var contextName in await GetAvailableContextsAsync(cancellationToken).ConfigureAwait(false))
        {
            var inspectArgs = new List<string>();
            if (!string.Equals(contextName, "default", StringComparison.Ordinal))
            {
                inspectArgs.Add("--context");
                inspectArgs.Add(contextName);
            }

            inspectArgs.AddRange(["inspect", "--type", "container", "--", containerName]);
            var inspect = await RunProcessCaptureAsync("docker", inspectArgs, cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                contexts.Add(contextName);
            }
        }

        return contexts;
    }

    protected static async Task<List<string>> GetAvailableContextsAsync(CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        foreach (var contextName in new[] { "containai-docker", "containai-secure", "docker-containai" })
        {
            var probe = await RunProcessCaptureAsync("docker", ["context", "inspect", contextName], cancellationToken).ConfigureAwait(false);
            if (probe.ExitCode == 0)
            {
                contexts.Add(contextName);
            }
        }

        contexts.Add("default");
        return contexts;
    }

    protected static async Task<ProcessResult> DockerCaptureForContextAsync(string context, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var dockerArgs = new List<string>();
        if (!string.Equals(context, "default", StringComparison.Ordinal))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return await RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

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

    protected static async Task<string?> ResolveDataVolumeFromContainerAsync(string containerName, string? explicitVolume, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            return explicitVolume;
        }

        var inspect = await DockerCaptureAsync(
            ["inspect", "--format", "{{range .Mounts}}{{if and (eq .Type \"volume\") (eq .Destination \"/mnt/agent-data\")}}{{.Name}}{{end}}{{end}}", containerName],
            cancellationToken).ConfigureAwait(false);

        if (inspect.ExitCode != 0)
        {
            return null;
        }

        var volumeName = inspect.StandardOutput.Trim();
        return string.IsNullOrWhiteSpace(volumeName) ? null : volumeName;
    }

    protected static async Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = operation();
        return await Task.FromResult(new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError)).ConfigureAwait(false);
    }

    protected static string NormalizeConfigKey(string key) => string.Equals(key, "agent", StringComparison.Ordinal)
            ? "agent.default"
            : key;

    protected static (string? Workspace, string? Error) ResolveWorkspaceScope(ParsedConfigCommand parsed, string normalizedKey)
    {
        if (!string.Equals(normalizedKey, "data_volume", StringComparison.Ordinal))
        {
            return (parsed.Workspace, null);
        }

        if (parsed.Global)
        {
            return (null, "data_volume is workspace-scoped and cannot be set globally");
        }

        var workspace = parsed.Workspace;
        if (string.IsNullOrWhiteSpace(workspace))
        {
            workspace = Directory.GetCurrentDirectory();
        }

        return (Path.GetFullPath(workspace), null);
    }

    protected static bool TryParseAgeDuration(string value, out TimeSpan duration)
    {
        duration = default;
        if (string.IsNullOrWhiteSpace(value) || value.Length < 2)
        {
            return false;
        }

        var suffix = value[^1];
        if (!int.TryParse(value[..^1], out var amount) || amount < 0)
        {
            return false;
        }

        duration = suffix switch
        {
            'd' or 'D' => TimeSpan.FromDays(amount),
            'h' or 'H' => TimeSpan.FromHours(amount),
            _ => default,
        };

        return duration != default || amount == 0;
    }

    protected static DateTimeOffset? ParseGcReferenceTime(string finishedAtRaw, string createdRaw)
    {
        if (!string.IsNullOrWhiteSpace(finishedAtRaw) &&
            !string.Equals(finishedAtRaw, "0001-01-01T00:00:00Z", StringComparison.Ordinal) &&
            DateTimeOffset.TryParse(finishedAtRaw, out var finishedAt))
        {
            return finishedAt;
        }

        return DateTimeOffset.TryParse(createdRaw, out var created) ? created : null;
    }

}
