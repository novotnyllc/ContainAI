using System.Security;

namespace ContainAI.Cli.Host;

internal static class SessionRuntimeInfrastructure
{
    public static string NormalizeWorkspacePath(string path) => Path.GetFullPath(ExpandHome(path));

    public static string ExpandHome(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || !value.StartsWith('~'))
        {
            return value;
        }

        var home = ResolveHomeDirectory();
        if (value.Length == 1)
        {
            return home;
        }

        return value[1] switch
        {
            '/' or '\\' => Path.Combine(home, value[2..]),
            _ => value,
        };
    }

    public static string ResolveHomeDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("HOME");
        }

        return string.IsNullOrWhiteSpace(home) ? Directory.GetCurrentDirectory() : home;
    }

    public static string ResolveConfigDirectory()
    {
        var xdgConfig = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var root = string.IsNullOrWhiteSpace(xdgConfig)
            ? Path.Combine(ResolveHomeDirectory(), ".config")
            : xdgConfig;
        return Path.Combine(root, "containai");
    }

    public static string ResolveUserConfigPath() => Path.Combine(ResolveConfigDirectory(), "config.toml");

    public static string ResolveSshPrivateKeyPath() => Path.Combine(ResolveConfigDirectory(), "id_containai");

    public static string ResolveSshPublicKeyPath() => Path.Combine(ResolveConfigDirectory(), "id_containai.pub");

    public static string ResolveKnownHostsFilePath() => Path.Combine(ResolveConfigDirectory(), "known_hosts");

    public static string ResolveSshConfigDir() => Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");

    public static string FindConfigFile(string workspace, string? explicitConfig)
    {
        if (!string.IsNullOrWhiteSpace(explicitConfig))
        {
            return Path.GetFullPath(ExpandHome(explicitConfig));
        }

        var current = Path.GetFullPath(workspace);
        while (!string.IsNullOrWhiteSpace(current))
        {
            var candidate = Path.Combine(current, ".containai", "config.toml");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            if (File.Exists(Path.Combine(current, ".git")) || Directory.Exists(Path.Combine(current, ".git")))
            {
                break;
            }

            var parent = Directory.GetParent(current);
            if (parent is null)
            {
                break;
            }

            current = parent.FullName;
        }

        var userConfig = ResolveUserConfigPath();
        return File.Exists(userConfig) ? userConfig : string.Empty;
    }

    public static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\\''", StringComparison.Ordinal);

    public static string ReplaceFirstToken(string knownHostsLine, string hostToken)
    {
        var firstSpace = knownHostsLine.IndexOf(' ');
        if (firstSpace <= 0)
        {
            return knownHostsLine;
        }

        return hostToken + knownHostsLine[firstSpace..];
    }

    public static string NormalizeNoValue(string value)
    {
        var trimmed = value.Trim();
        return string.Equals(trimmed, "<no value>", StringComparison.Ordinal) ? string.Empty : trimmed;
    }

    public static string SanitizeNameComponent(string value, string fallback) => ContainerNameGenerator.SanitizeNameComponent(value, fallback);

    public static string SanitizeHostname(string value)
    {
        var normalized = value.ToLowerInvariant().Replace('_', '-');
        var chars = normalized.Where(static ch => char.IsAsciiLetterOrDigit(ch) || ch == '-').ToArray();
        var cleaned = new string(chars);
        while (cleaned.Contains("--", StringComparison.Ordinal))
        {
            cleaned = cleaned.Replace("--", "-", StringComparison.Ordinal);
        }

        cleaned = cleaned.Trim('-');
        if (cleaned.Length > 63)
        {
            cleaned = cleaned[..63].TrimEnd('-');
        }

        return string.IsNullOrWhiteSpace(cleaned) ? "container" : cleaned;
    }

    public static string TrimTrailingDash(string value) => ContainerNameGenerator.TrimTrailingDash(value);

    public static string GenerateWorkspaceVolumeName(string workspace)
    {
        var repo = SanitizeNameComponent(Path.GetFileName(Path.TrimEndingDirectorySeparator(workspace)), "workspace");
        var branch = "nogit";
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmss");

        try
        {
            var result = CliWrapProcessRunner
                .RunCaptureAsync(
                    "git",
                    ["-C", workspace, "rev-parse", "--abbrev-ref", "HEAD"],
                    CancellationToken.None)
                .WaitAsync(TimeSpan.FromSeconds(2))
                .GetAwaiter()
                .GetResult();

            if (result.ExitCode == 0)
            {
                var branchValue = result.StandardOutput.Trim();
                if (!string.IsNullOrWhiteSpace(branchValue))
                {
                    branch = SanitizeNameComponent(branchValue.Split('/').LastOrDefault() ?? branchValue, "nogit");
                }
            }
        }
        catch (InvalidOperationException)
        {
        }
        catch (IOException)
        {
        }
        catch (TimeoutException)
        {
        }

        return $"{repo}-{branch}-{timestamp}";
    }

    public static string TrimOrFallback(string? value, string fallback)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? fallback : trimmed;
    }

    public static Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = operation();
        return Task.FromResult(new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError));
    }

    public static async Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        TextWriter errorWriter,
        CancellationToken cancellationToken)
    {
        try
        {
            return await CliWrapProcessRunner.RunInteractiveAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await errorWriter.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await errorWriter.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            await errorWriter.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
    }

    public static async Task<ProcessResult> RunProcessCaptureAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        try
        {
            var result = await CliWrapProcessRunner.RunCaptureAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
            return new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
    }

    public static async Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken)
    {
        if (string.Equals(context, "default", StringComparison.Ordinal))
        {
            return true;
        }

        var inspect = await RunProcessCaptureAsync("docker", ["context", "inspect", context], cancellationToken).ConfigureAwait(false);
        return inspect.ExitCode == 0;
    }

    public static async Task<ProcessResult> DockerCaptureAsync(string context, IReadOnlyList<string> dockerArgs, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        if (!string.IsNullOrWhiteSpace(context) && !string.Equals(context, "default", StringComparison.Ordinal))
        {
            args.Add("--context");
            args.Add(context);
        }

        args.AddRange(dockerArgs);
        return await RunProcessCaptureAsync("docker", args, cancellationToken).ConfigureAwait(false);
    }

    public static bool IsContainAiImage(string image)
    {
        if (string.IsNullOrWhiteSpace(image))
        {
            return false;
        }

        foreach (var prefix in SessionRuntimeConstants.ContainAiImagePrefixes)
        {
            if (image.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    public static bool IsValidVolumeName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 255)
        {
            return false;
        }

        if (!char.IsLetterOrDigit(name[0]))
        {
            return false;
        }

        foreach (var ch in name)
        {
            if (!(char.IsLetterOrDigit(ch) || ch is '_' or '.' or '-'))
            {
                return false;
            }
        }

        return true;
    }

    public static string ResolveImage(SessionCommandOptions options)
    {
        if (!string.IsNullOrWhiteSpace(options.ImageTag) && string.IsNullOrWhiteSpace(options.Template))
        {
            return $"{SessionRuntimeConstants.ContainAiRepo}:{options.ImageTag}";
        }

        if (string.Equals(options.Channel, "nightly", StringComparison.OrdinalIgnoreCase))
        {
            return $"{SessionRuntimeConstants.ContainAiRepo}:nightly";
        }

        return $"{SessionRuntimeConstants.ContainAiRepo}:{SessionRuntimeConstants.DefaultImageTag}";
    }

    public static string ResolveHostTimeZone()
    {
        try
        {
            return TimeZoneInfo.Local.Id;
        }
        catch (TimeZoneNotFoundException)
        {
            return "UTC";
        }
        catch (InvalidTimeZoneException)
        {
            return "UTC";
        }
        catch (SecurityException)
        {
            return "UTC";
        }
    }

    public static void ParsePortsFromSocketTable(string content, HashSet<int> destination)
    {
        foreach (var line in content.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length < 4)
            {
                continue;
            }

            var endpoint = parts[3];
            var separator = endpoint.LastIndexOf(':');
            if (separator <= 0 || separator >= endpoint.Length - 1)
            {
                continue;
            }

            if (int.TryParse(endpoint[(separator + 1)..], out var port) && port > 0)
            {
                destination.Add(port);
            }
        }
    }
}
