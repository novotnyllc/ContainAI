using System.Diagnostics;
using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed class NativeLifecycleCommandRuntime
{
    private static readonly string[] ContainAiImagePrefixes =
    [
        "containai:",
        "ghcr.io/containai/",
        "ghcr.io/novotnyllc/containai",
    ];

    private readonly TextWriter _stdout;
    private readonly TextWriter _stderr;

    public NativeLifecycleCommandRuntime(TextWriter? stdout = null, TextWriter? stderr = null)
    {
        _stdout = stdout ?? Console.Out;
        _stderr = stderr ?? Console.Error;
    }

    public Task<int> RunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count == 0)
        {
            return Task.FromResult(1);
        }

        return args[0] switch
        {
            "completion" => RunCompletionAsync(args, cancellationToken),
            "config" => RunConfigAsync(args, cancellationToken),
            "template" => RunTemplateAsync(args, cancellationToken),
            "ssh" => RunSshAsync(args, cancellationToken),
            "stop" => RunStopAsync(args, cancellationToken),
            "gc" => RunGcAsync(args, cancellationToken),
            _ => Task.FromResult(1),
        };
    }

    private Task<int> RunCompletionAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var shell = args.Count > 1 ? args[1] : string.Empty;
        if (shell is "" or "-h" or "--help")
        {
            _stdout.WriteLine("Usage: cai completion <bash|zsh>");
            return Task.FromResult(0);
        }

        if (shell.Equals("bash", StringComparison.Ordinal))
        {
            _stdout.WriteLine(BuildBashCompletionScript());
            return Task.FromResult(0);
        }

        if (shell.Equals("zsh", StringComparison.Ordinal))
        {
            _stdout.WriteLine(BuildZshCompletionScript());
            return Task.FromResult(0);
        }

        _stderr.WriteLine($"Unknown shell: {shell}");
        return Task.FromResult(1);
    }

    private async Task<int> RunConfigAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2)
        {
            await _stderr.WriteLineAsync("Usage: cai config <list|get|set|unset> [options]").ConfigureAwait(false);
            return 1;
        }

        var parsed = ParseConfigOptions(args.Skip(1).ToArray());
        if (parsed.Error is not null)
        {
            await _stderr.WriteLineAsync(parsed.Error).ConfigureAwait(false);
            return 1;
        }

        var configPath = ResolveUserConfigPath();
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        if (!File.Exists(configPath))
        {
            await File.WriteAllTextAsync(configPath, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        return parsed.Action switch
        {
            "list" => await ConfigListAsync(configPath, cancellationToken).ConfigureAwait(false),
            "get" => await ConfigGetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            "set" => await ConfigSetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            "unset" => await ConfigUnsetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            _ => 1,
        };
    }

    private async Task<int> ConfigListAsync(string configPath, CancellationToken cancellationToken)
    {
        var parseResult = await RunParseTomlAsync(["--file", configPath, "--json"], cancellationToken).ConfigureAwait(false);
        if (parseResult.ExitCode != 0)
        {
            await _stderr.WriteLineAsync(parseResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await _stdout.WriteLineAsync(parseResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> ConfigGetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key))
        {
            await _stderr.WriteLineAsync("config get requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await _stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            var wsResult = await RunParseTomlAsync(
                ["--file", configPath, "--get-workspace", workspaceScope.Workspace],
                cancellationToken).ConfigureAwait(false);
            if (wsResult.ExitCode != 0)
            {
                return 1;
            }

            using var wsJson = JsonDocument.Parse(wsResult.StandardOutput);
            if (wsJson.RootElement.ValueKind == JsonValueKind.Object &&
                wsJson.RootElement.TryGetProperty(parsed.Key, out var wsValue))
            {
                await _stdout.WriteLineAsync(wsValue.ToString()).ConfigureAwait(false);
                return 0;
            }

            return 1;
        }

        var getResult = await RunParseTomlAsync(
            ["--file", configPath, "--key", normalizedKey],
            cancellationToken).ConfigureAwait(false);

        if (getResult.ExitCode != 0)
        {
            return 1;
        }

        await _stdout.WriteLineAsync(getResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> ConfigSetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key) || parsed.Value is null)
        {
            await _stderr.WriteLineAsync("config set requires <key> <value>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await _stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        ProcessResult setResult;
        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            setResult = await RunParseTomlAsync(
                ["--file", configPath, "--set-workspace-key", workspaceScope.Workspace, parsed.Key, parsed.Value],
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            setResult = await RunParseTomlAsync(
                ["--file", configPath, "--set-key", normalizedKey, parsed.Value],
                cancellationToken).ConfigureAwait(false);
        }

        if (setResult.ExitCode != 0)
        {
            await _stderr.WriteLineAsync(setResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> ConfigUnsetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key))
        {
            await _stderr.WriteLineAsync("config unset requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await _stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        ProcessResult unsetResult;
        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            unsetResult = await RunParseTomlAsync(
                ["--file", configPath, "--unset-workspace-key", workspaceScope.Workspace, parsed.Key],
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            unsetResult = await RunParseTomlAsync(
                ["--file", configPath, "--unset-key", normalizedKey],
                cancellationToken).ConfigureAwait(false);
        }

        if (unsetResult.ExitCode != 0)
        {
            await _stderr.WriteLineAsync(unsetResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> RunTemplateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2 || args[1] is "-h" or "--help")
        {
            await _stdout.WriteLineAsync("Usage: cai template upgrade [name] [--dry-run]").ConfigureAwait(false);
            return 0;
        }

        if (!string.Equals(args[1], "upgrade", StringComparison.Ordinal))
        {
            await _stderr.WriteLineAsync($"Unknown template subcommand: {args[1]}").ConfigureAwait(false);
            return 1;
        }

        var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
        var templateName = args.Skip(2).FirstOrDefault(static token => !token.StartsWith("-", StringComparison.Ordinal));

        var templatesRoot = ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            await _stderr.WriteLineAsync($"Template directory not found: {templatesRoot}").ConfigureAwait(false);
            return 1;
        }

        var dockerfiles = string.IsNullOrWhiteSpace(templateName)
            ? Directory.EnumerateDirectories(templatesRoot)
                .Select(path => Path.Combine(path, "Dockerfile"))
                .Where(File.Exists)
                .ToArray()
            : [Path.Combine(templatesRoot, templateName, "Dockerfile")];

        var changedCount = 0;
        foreach (var dockerfile in dockerfiles)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!File.Exists(dockerfile))
            {
                continue;
            }

            var content = await File.ReadAllTextAsync(dockerfile, cancellationToken).ConfigureAwait(false);
            if (!TryUpgradeDockerfile(content, out var updated))
            {
                continue;
            }

            changedCount++;
            if (dryRun)
            {
                await _stdout.WriteLineAsync($"Would upgrade {dockerfile}").ConfigureAwait(false);
                continue;
            }

            await File.WriteAllTextAsync(dockerfile, updated, cancellationToken).ConfigureAwait(false);
            await _stdout.WriteLineAsync($"Upgraded {dockerfile}").ConfigureAwait(false);
        }

        if (changedCount == 0)
        {
            await _stdout.WriteLineAsync("No template changes required.").ConfigureAwait(false);
        }

        return 0;
    }

    private async Task<int> RunSshAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2 || args[1] is "-h" or "--help")
        {
            await _stdout.WriteLineAsync("Usage: cai ssh cleanup [--dry-run]").ConfigureAwait(false);
            return 0;
        }

        if (!string.Equals(args[1], "cleanup", StringComparison.Ordinal))
        {
            await _stderr.WriteLineAsync($"Unknown ssh subcommand: {args[1]}").ConfigureAwait(false);
            return 1;
        }

        var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
        var sshDir = Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");
        if (!Directory.Exists(sshDir))
        {
            return 0;
        }

        var removed = 0;
        foreach (var file in Directory.EnumerateFiles(sshDir, "*.conf"))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var containerName = Path.GetFileNameWithoutExtension(file);
            var exists = await DockerContainerExistsAsync(containerName, cancellationToken).ConfigureAwait(false);
            if (exists)
            {
                continue;
            }

            removed++;
            if (dryRun)
            {
                await _stdout.WriteLineAsync($"Would remove {file}").ConfigureAwait(false);
                continue;
            }

            File.Delete(file);
            await _stdout.WriteLineAsync($"Removed {file}").ConfigureAwait(false);
        }

        if (removed == 0)
        {
            await _stdout.WriteLineAsync("No stale SSH configs found.").ConfigureAwait(false);
        }

        return 0;
    }

    private async Task<int> RunStopAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var containerName = GetOptionValue(args, "--container");
        var stopAll = args.Contains("--all", StringComparer.Ordinal);
        var remove = args.Contains("--remove", StringComparer.Ordinal);
        var force = args.Contains("--force", StringComparer.Ordinal);

        if (!ValidateStopArgs(args, out var stopValidationError))
        {
            await _stderr.WriteLineAsync(stopValidationError).ConfigureAwait(false);
            return 1;
        }

        if (stopAll && !string.IsNullOrWhiteSpace(containerName))
        {
            await _stderr.WriteLineAsync("--all and --container are mutually exclusive").ConfigureAwait(false);
            return 1;
        }

        var targets = new List<string>();
        if (!string.IsNullOrWhiteSpace(containerName))
        {
            targets.Add(containerName);
        }
        else if (stopAll)
        {
            var list = await DockerCaptureAsync(["ps", "-aq", "--filter", "label=containai.managed=true"], cancellationToken).ConfigureAwait(false);
            if (list.ExitCode != 0)
            {
                await _stderr.WriteLineAsync(list.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }

            targets.AddRange(list.StandardOutput
                .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        }
        else
        {
            await _stderr.WriteLineAsync("Usage: cai stop --all | --container <name> [--remove]").ConfigureAwait(false);
            return 1;
        }

        var failures = 0;
        foreach (var target in targets)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var stopExitCode = await DockerRunAsync(["stop", target], cancellationToken).ConfigureAwait(false);
            if (stopExitCode != 0)
            {
                failures++;
                await _stderr.WriteLineAsync($"Failed to stop container: {target}").ConfigureAwait(false);
                if (!force)
                {
                    continue;
                }
            }

            if (remove)
            {
                var removeExitCode = await DockerRunAsync(["rm", "-f", target], cancellationToken).ConfigureAwait(false);
                if (removeExitCode != 0)
                {
                    failures++;
                    await _stderr.WriteLineAsync($"Failed to remove container: {target}").ConfigureAwait(false);
                }
            }
        }

        return failures == 0 ? 0 : 1;
    }

    private async Task<int> RunGcAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
        var force = args.Contains("--force", StringComparer.Ordinal);
        var includeImages = args.Contains("--images", StringComparer.Ordinal);
        var ageValue = GetOptionValue(args, "--age") ?? "30d";
        if (!TryParseAgeDuration(ageValue, out var minimumAge))
        {
            await _stderr.WriteLineAsync($"Invalid --age value: {ageValue}").ConfigureAwait(false);
            return 1;
        }

        var candidates = await DockerCaptureAsync(
            ["ps", "-aq", "--filter", "label=containai.managed=true", "--filter", "status=exited", "--filter", "status=created"],
            cancellationToken).ConfigureAwait(false);

        if (candidates.ExitCode != 0)
        {
            await _stderr.WriteLineAsync(candidates.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        var containerIds = candidates.StandardOutput
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var failures = 0;
        foreach (var containerId in containerIds)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var inspect = await DockerCaptureAsync(
                ["inspect", "--format", "{{.State.Status}}|{{.State.FinishedAt}}|{{.Created}}|{{with index .Config.Labels \"containai.keep\"}}{{.}}{{end}}", containerId],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode != 0)
            {
                failures++;
                continue;
            }

            var inspectFields = inspect.StandardOutput.Trim().Split('|');
            if (inspectFields.Length < 4)
            {
                continue;
            }

            var state = inspectFields[0];
            if (string.Equals(state, "running", StringComparison.Ordinal))
            {
                continue;
            }

            if (string.Equals(inspectFields[3], "true", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var referenceTime = ParseGcReferenceTime(inspectFields[1], inspectFields[2]);
            if (referenceTime is null)
            {
                continue;
            }

            if (DateTimeOffset.UtcNow - referenceTime.Value < minimumAge)
            {
                continue;
            }

            if (dryRun)
            {
                await _stdout.WriteLineAsync($"Would remove container {containerId}").ConfigureAwait(false);
            }
            else
            {
                var removeResult = await DockerRunAsync(["rm", "-f", containerId], cancellationToken).ConfigureAwait(false);
                if (removeResult != 0)
                {
                    failures++;
                }
            }
        }

        if (includeImages)
        {
            if (!dryRun && !force)
            {
                await _stderr.WriteLineAsync("Use --force with --images to remove images.").ConfigureAwait(false);
                return 1;
            }

            var images = await DockerCaptureAsync(["images", "--format", "{{.Repository}}:{{.Tag}} {{.ID}}"], cancellationToken).ConfigureAwait(false);
            if (images.ExitCode == 0)
            {
                foreach (var line in images.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    if (parts.Length != 2)
                    {
                        continue;
                    }

                    var reference = parts[0];
                    var imageId = parts[1];
                    if (!ContainAiImagePrefixes.Any(prefix => reference.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
                    {
                        continue;
                    }

                    if (dryRun)
                    {
                        await _stdout.WriteLineAsync($"Would remove image {reference}").ConfigureAwait(false);
                    }
                    else
                    {
                        var removeImageResult = await DockerRunAsync(["rmi", imageId], cancellationToken).ConfigureAwait(false);
                        if (removeImageResult != 0)
                        {
                            failures++;
                        }
                    }
                }
            }
        }

        return failures == 0 ? 0 : 1;
    }

    private async Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
    {
        var result = await DockerRunAsync(["inspect", "--type", "container", containerName], cancellationToken).ConfigureAwait(false);
        return result == 0;
    }

    private async Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        return result.ExitCode;
    }

    private async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
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

    private async Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
    {
        var containAiContextProbe = await RunProcessCaptureAsync(
            "docker",
            ["context", "inspect", "containai-docker"],
            cancellationToken).ConfigureAwait(false);

        return containAiContextProbe.ExitCode == 0 ? "containai-docker" : null;
    }

    private static string ResolveHomeDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("HOME");
        }

        return string.IsNullOrWhiteSpace(home) ? Directory.GetCurrentDirectory() : home;
    }

    private static string ResolveUserConfigPath()
    {
        var home = ResolveHomeDirectory();
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai", "config.toml");
    }

    private static string ResolveTemplatesDirectory()
    {
        var home = ResolveHomeDirectory();
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai", "templates");
    }

    private async Task<ProcessResult> RunParseTomlAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var parseTomlPath = ResolveParseTomlPath();
        if (string.IsNullOrWhiteSpace(parseTomlPath))
        {
            return new ProcessResult(1, string.Empty, "parse-toml.py not found");
        }

        var allArgs = new List<string>(capacity: args.Count + 1)
        {
            parseTomlPath,
        };
        allArgs.AddRange(args);

        return await RunProcessCaptureAsync("python3", allArgs, cancellationToken).ConfigureAwait(false);
    }

    private static string? ResolveParseTomlPath()
    {
        foreach (var root in new[] { AppContext.BaseDirectory, Directory.GetCurrentDirectory() })
        {
            var current = Path.GetFullPath(root);
            while (!string.IsNullOrWhiteSpace(current))
            {
                foreach (var candidate in new[]
                         {
                             Path.Combine(current, "parse-toml.py"),
                             Path.Combine(current, "src", "parse-toml.py"),
                         })
                {
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }

                var parent = Directory.GetParent(current);
                if (parent is null)
                {
                    break;
                }

                current = parent.FullName;
            }
        }

        return null;
    }

    private static string NormalizeConfigKey(string key)
    {
        return string.Equals(key, "agent", StringComparison.Ordinal)
            ? "agent.default"
            : key;
    }

    private static (string? Workspace, string? Error) ResolveWorkspaceScope(ParsedConfigCommand parsed, string normalizedKey)
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

    private static ParsedConfigCommand ParseConfigOptions(string[] args)
    {
        var global = false;
        string? workspace = null;
        var tail = new List<string>();

        for (var index = 0; index < args.Length; index++)
        {
            var token = args[index];
            if (token is "-g" or "--global")
            {
                global = true;
                continue;
            }

            if (token == "--workspace")
            {
                if (index + 1 >= args.Length)
                {
                    return ParsedConfigCommand.WithError("--workspace requires a value");
                }

                workspace = args[++index];
                continue;
            }

            if (token.StartsWith("--workspace=", StringComparison.Ordinal))
            {
                workspace = token[12..];
                continue;
            }

            if (token == "--verbose")
            {
                continue;
            }

            tail.Add(token);
        }

        if (tail.Count == 0)
        {
            return ParsedConfigCommand.WithError("config requires a subcommand");
        }

        var action = tail[0];
        return action switch
        {
            "list" => new ParsedConfigCommand(action, null, null, global, workspace, null),
            "get" when tail.Count >= 2 => new ParsedConfigCommand(action, tail[1], null, global, workspace, null),
            "set" when tail.Count >= 3 => new ParsedConfigCommand(action, tail[1], tail[2], global, workspace, null),
            "unset" when tail.Count >= 2 => new ParsedConfigCommand(action, tail[1], null, global, workspace, null),
            _ => ParsedConfigCommand.WithError("invalid config command usage"),
        };
    }

    private static bool ValidateStopArgs(IReadOnlyList<string> args, out string error)
    {
        for (var index = 1; index < args.Count; index++)
        {
            var token = args[index];
            if (token is "--all" or "--remove" or "--force" or "--export" or "--verbose")
            {
                continue;
            }

            if (token == "--container")
            {
                if (index + 1 >= args.Count || args[index + 1].StartsWith("-", StringComparison.Ordinal))
                {
                    error = "--container requires a value";
                    return false;
                }

                index++;
                continue;
            }

            if (token.StartsWith("--container=", StringComparison.Ordinal))
            {
                if (token.Length <= "--container=".Length)
                {
                    error = "--container requires a value";
                    return false;
                }

                continue;
            }

            error = $"Unknown stop option: {token}";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static bool TryParseAgeDuration(string value, out TimeSpan duration)
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

    private static DateTimeOffset? ParseGcReferenceTime(string finishedAtRaw, string createdRaw)
    {
        if (!string.IsNullOrWhiteSpace(finishedAtRaw) &&
            !string.Equals(finishedAtRaw, "0001-01-01T00:00:00Z", StringComparison.Ordinal) &&
            DateTimeOffset.TryParse(finishedAtRaw, out var finishedAt))
        {
            return finishedAt;
        }

        return DateTimeOffset.TryParse(createdRaw, out var created) ? created : null;
    }

    private static bool TryUpgradeDockerfile(string content, out string updated)
    {
        updated = content;
        if (content.Contains("${BASE_IMAGE}", StringComparison.Ordinal) &&
            content.Contains("ARG BASE_IMAGE", StringComparison.Ordinal))
        {
            return false;
        }

        var lines = content.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        for (var index = 0; index < lines.Length; index++)
        {
            var trimmed = lines[index].TrimStart();
            if (!trimmed.StartsWith("FROM ", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var fromPayload = trimmed[5..].Trim();
            if (string.IsNullOrWhiteSpace(fromPayload))
            {
                return false;
            }

            string baseImage;
            string? stage = null;
            var asIndex = fromPayload.IndexOf(" AS ", StringComparison.OrdinalIgnoreCase);
            if (asIndex > 0)
            {
                baseImage = fromPayload[..asIndex].Trim();
                stage = fromPayload[(asIndex + 4)..].Trim();
            }
            else
            {
                baseImage = fromPayload;
            }

            var indent = lines[index][..(lines[index].Length - trimmed.Length)];
            var fromReplacement = string.IsNullOrWhiteSpace(stage)
                ? $"{indent}FROM ${{BASE_IMAGE}}"
                : $"{indent}FROM ${{BASE_IMAGE}} AS {stage}";

            var replacement = new List<string>
            {
                $"{indent}ARG BASE_IMAGE={baseImage}",
                fromReplacement,
            };

            lines[index] = string.Join("\n", replacement);
            updated = string.Join("\n", lines);
            if (content.EndsWith("\n", StringComparison.Ordinal) && !updated.EndsWith("\n", StringComparison.Ordinal))
            {
                updated += "\n";
            }

            return true;
        }

        return false;
    }

    private static string? GetOptionValue(IReadOnlyList<string> args, string option)
    {
        for (var index = 0; index < args.Count; index++)
        {
            if (string.Equals(args[index], option, StringComparison.Ordinal))
            {
                if (index + 1 < args.Count)
                {
                    return args[index + 1];
                }

                return string.Empty;
            }

            if (args[index].StartsWith(option + "=", StringComparison.Ordinal))
            {
                return args[index][(option.Length + 1)..];
            }
        }

        return null;
    }

    private static string BuildBashCompletionScript()
    {
        return """
# ContainAI bash completion
_cai_completions() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local cmds="run shell exec doctor setup validate docker import export sync stop status gc ssh links config template update refresh uninstall completion version help acp"
  COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
}
complete -F _cai_completions cai
""";
    }

    private static string BuildZshCompletionScript()
    {
        return """
#compdef cai

_cai() {
  local -a commands
  commands=(
    'run:Start or attach to sandbox container'
    'shell:Open interactive shell in running container'
    'exec:Run command in container'
    'docker:Run docker with ContainAI context'
    'status:Show container status'
    'stop:Stop containers'
    'gc:Garbage collect stale resources'
    'ssh:Manage SSH configuration'
    'config:Manage settings'
    'template:Manage templates'
    'completion:Generate completion scripts'
    'version:Show version'
    'help:Show help'
    'acp:ACP tooling'
  )
  _describe 'command' commands
}

_cai "$@"
""";
    }

    private static async Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo(fileName)
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
        };

        foreach (var argument in arguments)
        {
            process.StartInfo.ArgumentList.Add(argument);
        }

        try
        {
            if (!process.Start())
            {
                return new ProcessResult(1, string.Empty, $"Failed to start {fileName}");
            }
        }
        catch (Exception ex)
        {
            return new ProcessResult(1, string.Empty, ex.Message);
        }

        using var cancellationRegistration = cancellationToken.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                // Ignore cancellation cleanup failures.
            }
        });

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);

        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

        return new ProcessResult(
            process.ExitCode,
            await stdoutTask.ConfigureAwait(false),
            await stderrTask.ConfigureAwait(false));
    }

    private readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);

    private readonly record struct ParsedConfigCommand(
        string Action,
        string? Key,
        string? Value,
        bool Global,
        string? Workspace,
        string? Error)
    {
        public static ParsedConfigCommand WithError(string error)
            => new(string.Empty, null, null, false, null, error);
    }
}
