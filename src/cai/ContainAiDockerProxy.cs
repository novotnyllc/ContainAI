using System.ComponentModel;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal static partial class ContainAiDockerProxy
{
    private const string DefaultContext = "containai-docker";
    private const string DefaultDataVolume = "containai-data";
    private const int SshPortRangeStart = 2400;
    private const int SshPortRangeEnd = 2499;


    public static async Task<int> RunAsync(IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr, CancellationToken cancellationToken)
    {
        var contextName = Environment.GetEnvironmentVariable("CONTAINAI_DOCKER_CONTEXT");
        if (string.IsNullOrWhiteSpace(contextName))
        {
            contextName = DefaultContext;
        }

        var (dockerArgs, verbose, quiet) = ParseWrapperFlags(args);

        if (!IsContainerCreateCommand(dockerArgs))
        {
            var useContainAiContext = await ShouldUseContainAiContextAsync(dockerArgs, contextName, cancellationToken).ConfigureAwait(false);
            return await RunDockerInteractiveAsync(useContainAiContext
                    ? PrependContext(contextName, dockerArgs)
                    : dockerArgs,
                cancellationToken).ConfigureAwait(false);
        }

        var (configFile, localFolder) = ExtractDevcontainerLabels(dockerArgs);
        if (string.IsNullOrWhiteSpace(configFile) || !TryReadFeatureSettings(configFile!, stderr, out var settings))
        {
            return await RunDockerInteractiveAsync(dockerArgs, cancellationToken).ConfigureAwait(false);
        }

        if (!settings.HasContainAiFeature)
        {
            return await RunDockerInteractiveAsync(dockerArgs, cancellationToken).ConfigureAwait(false);
        }

        var contextProbe = await RunDockerCaptureAsync(["context", "inspect", contextName!], cancellationToken).ConfigureAwait(false);
        if (contextProbe.ExitCode != 0)
        {
            await stderr.WriteLineAsync("ContainAI: Not set up. Run: cai setup").ConfigureAwait(false);
            return 1;
        }

        var workspaceName = Path.GetFileName(localFolder ?? "workspace");
        if (string.IsNullOrWhiteSpace(workspaceName))
        {
            workspaceName = "workspace";
        }

        var workspaceNameSanitized = SanitizeWorkspaceName(workspaceName);
        var containAiConfigDir = Path.Combine(ResolveHomeDirectory(), ".config", "containai");
        var lockPath = Path.Combine(containAiConfigDir, ".ssh-port.lock");

        var sshPort = await WithPortLockAsync(lockPath, async () =>
        {
            return await AllocateSshPortAsync(containAiConfigDir, contextName!, workspaceName, workspaceNameSanitized, cancellationToken).ConfigureAwait(false);
        }, cancellationToken).ConfigureAwait(false);

        var mountVolume = await ValidateVolumeCredentialsAsync(contextName!, settings.DataVolume, settings.EnableCredentials, quiet, cancellationToken).ConfigureAwait(false);

        var modifiedArgs = new List<string>(dockerArgs.Count + 24);
        foreach (var token in dockerArgs)
        {
            modifiedArgs.Add(token);
            if (!string.Equals(token, "run", StringComparison.Ordinal) && !string.Equals(token, "create", StringComparison.Ordinal))
            {
                continue;
            }

            modifiedArgs.Add("--runtime=sysbox-runc");

            if (mountVolume)
            {
                var volumeExists = await RunDockerCaptureAsync(["--context", contextName!, "volume", "inspect", settings.DataVolume], cancellationToken).ConfigureAwait(false);
                if (volumeExists.ExitCode == 0)
                {
                    modifiedArgs.Add("--mount");
                    modifiedArgs.Add($"type=volume,src={settings.DataVolume},dst=/mnt/agent-data,readonly=false");
                }
                else if (!quiet)
                {
                    await stderr.WriteLineAsync($"[cai-docker] Warning: Data volume {settings.DataVolume} not found - skipping mount").ConfigureAwait(false);
                }
            }

            modifiedArgs.Add("-e");
            modifiedArgs.Add($"CONTAINAI_SSH_PORT={sshPort}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add("containai.managed=true");
            modifiedArgs.Add("--label");
            modifiedArgs.Add("containai.type=devcontainer");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.devcontainer.workspace={workspaceName}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.data-volume={settings.DataVolume}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.ssh-port={sshPort}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.created={DateTime.UtcNow:yyyy-MM-ddTHH:mm:ssZ}");
        }

        await UpdateSshConfigAsync(workspaceNameSanitized, sshPort, settings.RemoteUser, stderr, cancellationToken).ConfigureAwait(false);

        if (verbose && !quiet)
        {
            await stderr.WriteLineAsync($"[cai-docker] Executing: docker --context {contextName} {string.Join(' ', modifiedArgs)}").ConfigureAwait(false);
        }

        return await RunDockerInteractiveAsync(PrependContext(contextName!, modifiedArgs), cancellationToken).ConfigureAwait(false);
    }

    internal static string StripJsoncComments(string content)
    {
        var builder = new StringBuilder(content.Length);
        var inString = false;
        var escape = false;

        for (var index = 0; index < content.Length; index++)
        {
            var current = content[index];

            if (escape)
            {
                builder.Append(current);
                escape = false;
                continue;
            }

            if (current == '\\' && inString)
            {
                builder.Append(current);
                escape = true;
                continue;
            }

            if (current == '"')
            {
                inString = !inString;
                builder.Append(current);
                continue;
            }

            if (!inString && current == '/' && index + 1 < content.Length)
            {
                var next = content[index + 1];
                if (next == '/')
                {
                    while (index < content.Length && content[index] != '\n')
                    {
                        index++;
                    }

                    if (index < content.Length)
                    {
                        builder.Append('\n');
                    }

                    continue;
                }

                if (next == '*')
                {
                    index += 2;
                    while (index + 1 < content.Length && !(content[index] == '*' && content[index + 1] == '/'))
                    {
                        if (content[index] == '\n')
                        {
                            builder.Append('\n');
                        }

                        index++;
                    }

                    index++;
                    continue;
                }
            }

            builder.Append(current);
        }

        return builder.ToString();
    }

    internal static (string? ConfigFile, string? LocalFolder) ExtractDevcontainerLabels(IReadOnlyList<string> args)
    {
        string? configFile = null;
        string? localFolder = null;

        for (var index = 0; index < args.Count; index++)
        {
            var token = args[index];
            if (string.Equals(token, "--label", StringComparison.Ordinal) && index + 1 < args.Count)
            {
                ParseLabel(args[index + 1], ref configFile, ref localFolder);
                index++;
                continue;
            }

            if (token.StartsWith("--label=", StringComparison.Ordinal))
            {
                ParseLabel(token[8..], ref configFile, ref localFolder);
            }
        }

        return (configFile, localFolder);
    }

    internal static bool IsContainerCreateCommand(IReadOnlyList<string> args)
    {
        var firstToken = string.Empty;
        var secondToken = string.Empty;

        foreach (var arg in args)
        {
            if (arg.StartsWith('-'))
            {
                continue;
            }

            if (string.IsNullOrEmpty(firstToken))
            {
                firstToken = arg;
                continue;
            }

            secondToken = arg;
            break;
        }

        if (string.Equals(firstToken, "run", StringComparison.Ordinal) ||
            string.Equals(firstToken, "create", StringComparison.Ordinal))
        {
            return true;
        }

        return string.Equals(firstToken, "container", StringComparison.Ordinal) &&
               (string.Equals(secondToken, "run", StringComparison.Ordinal) ||
                string.Equals(secondToken, "create", StringComparison.Ordinal));
    }

    internal static string SanitizeWorkspaceName(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "workspace";
        }

        var replaced = NonWorkspaceCharacterRegex().Replace(value, "-");
        replaced = MultiHyphenRegex().Replace(replaced, "-").Trim('-');
        return string.IsNullOrWhiteSpace(replaced) ? "workspace" : replaced;
    }

    private static async Task<bool> ShouldUseContainAiContextAsync(IReadOnlyList<string> args, string contextName, CancellationToken cancellationToken)
    {
        foreach (var arg in args)
        {
            if (string.Equals(arg, "--context", StringComparison.Ordinal) || arg.StartsWith("--context=", StringComparison.Ordinal))
            {
                return false;
            }

            if (arg.Contains("devcontainer.", StringComparison.Ordinal) || arg.Contains("containai.", StringComparison.Ordinal))
            {
                return true;
            }
        }

        var subcommand = GetFirstSubcommand(args);
        if (string.IsNullOrWhiteSpace(subcommand))
        {
            return false;
        }

        if (!ContainerTargetingSubcommands.Contains(subcommand))
        {
            return false;
        }

        var containerName = GetContainerNameArg(args, subcommand);
        if (string.IsNullOrWhiteSpace(containerName))
        {
            return false;
        }

        var probe = await RunDockerCaptureAsync(["--context", contextName, "inspect", containerName], cancellationToken).ConfigureAwait(false);
        return probe.ExitCode == 0;
    }

    private static async Task<bool> ValidateVolumeCredentialsAsync(
        string contextName,
        string dataVolume,
        bool enableCredentials,
        bool quiet,
        CancellationToken cancellationToken)
    {
        if (enableCredentials)
        {
            return true;
        }

        var marker = await RunDockerCaptureAsync(
            ["--context", contextName, "run", "--rm", "-v", $"{dataVolume}:/vol:ro", "alpine", "test", "-f", "/vol/.containai-no-secrets"],
            cancellationToken).ConfigureAwait(false);

        if (marker.ExitCode == 0)
        {
            return true;
        }

        if (!quiet)
        {
            await Console.Error.WriteLineAsync($"[cai-docker] Warning: volume {dataVolume} may contain credentials").ConfigureAwait(false);
            await Console.Error.WriteLineAsync("[cai-docker] Warning: set enableCredentials=true for trusted repositories").ConfigureAwait(false);
        }

        return false;
    }

    private static async Task<string> AllocateSshPortAsync(
        string containAiConfigDir,
        string contextName,
        string workspaceName,
        string workspaceSafe,
        CancellationToken cancellationToken)
    {
        var portDir = Path.Combine(containAiConfigDir, "ports");
        Directory.CreateDirectory(portDir);

        var portFile = Path.Combine(portDir, $"devcontainer-{workspaceSafe}");
        if (File.Exists(portFile))
        {
            var content = (await File.ReadAllTextAsync(portFile, cancellationToken).ConfigureAwait(false)).Trim();
            if (int.TryParse(content, out var existingPort))
            {
                if (!IsPortInUse(existingPort))
                {
                    return existingPort.ToString();
                }

                var existingContainerPort = await RunDockerCaptureAsync(
                    [
                        "--context", contextName,
                        "ps", "-a",
                        "--filter", $"label=containai.devcontainer.workspace={workspaceName}",
                        "--filter", "label=containai.ssh-port",
                        "--format", "{{.Label \"containai.ssh-port\"}}"
                    ],
                    cancellationToken).ConfigureAwait(false);

                if (existingContainerPort.ExitCode == 0 &&
                    string.Equals(existingContainerPort.StandardOutput.Trim(), content, StringComparison.Ordinal))
                {
                    return content;
                }
            }
        }

        var reservedPorts = new HashSet<int>();
        var labelPorts = await RunDockerCaptureAsync(
            ["--context", contextName, "ps", "-a", "--filter", "label=containai.ssh-port", "--format", "{{.Label \"containai.ssh-port\"}}"],
            cancellationToken).ConfigureAwait(false);

        if (labelPorts.ExitCode == 0)
        {
            foreach (var line in SplitLines(labelPorts.StandardOutput))
            {
                if (int.TryParse(line, out var parsedPort))
                {
                    reservedPorts.Add(parsedPort);
                }
            }
        }

        foreach (var file in Directory.EnumerateFiles(portDir))
        {
            try
            {
                var fileText = (await File.ReadAllTextAsync(file, cancellationToken).ConfigureAwait(false)).Trim();
                if (int.TryParse(fileText, out var parsedPort))
                {
                    reservedPorts.Add(parsedPort);
                }
            }
            catch (IOException ex)
            {
                // Ignore stale files and continue allocation.
                _ = ex;
            }
            catch (UnauthorizedAccessException ex)
            {
                // Ignore stale files and continue allocation.
                _ = ex;
            }
        }

        for (var port = SshPortRangeStart; port <= SshPortRangeEnd; port++)
        {
            if (reservedPorts.Contains(port) || IsPortInUse(port))
            {
                continue;
            }

            await File.WriteAllTextAsync(portFile, port.ToString(), cancellationToken).ConfigureAwait(false);
            return port.ToString();
        }

        return "2322";
    }

    private static bool IsPortInUse(int port)
    {
        try
        {
            return IPGlobalProperties.GetIPGlobalProperties()
                .GetActiveTcpListeners()
                .Any(endpoint => endpoint.Port == port);
        }
        catch (NetworkInformationException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    private static async Task UpdateSshConfigAsync(string workspaceName, string sshPort, string remoteUser, TextWriter stderr, CancellationToken cancellationToken)
    {
        var home = ResolveHomeDirectory();
        var sshRoot = Path.Combine(home, ".ssh");
        var containAiSshDir = Path.Combine(sshRoot, "containai.d");
        Directory.CreateDirectory(sshRoot);
        Directory.CreateDirectory(containAiSshDir);

        var userConfigPath = Path.Combine(sshRoot, "config");
        var includeLine = "Include ~/.ssh/containai.d/*.conf";

        if (!File.Exists(userConfigPath))
        {
            await File.WriteAllTextAsync(userConfigPath, includeLine + Environment.NewLine, cancellationToken).ConfigureAwait(false);
        }
        else
        {
            var existing = await File.ReadAllTextAsync(userConfigPath, cancellationToken).ConfigureAwait(false);
            var filtered = existing
                .Split('\n')
                .Where(line => !ContainAiIncludeRegex().IsMatch(line))
                .ToArray();

            var merged = includeLine + Environment.NewLine + Environment.NewLine + string.Join(Environment.NewLine, filtered).TrimStart();
            await File.WriteAllTextAsync(userConfigPath, merged.TrimEnd() + Environment.NewLine, cancellationToken).ConfigureAwait(false);
        }

        var hostAlias = $"containai-devcontainer-{workspaceName}";
        var configFile = Path.Combine(containAiSshDir, $"devcontainer-{workspaceName}.conf");
        var builder = new StringBuilder();
        builder.AppendLine($"# ContainAI SSH config for devcontainer: {workspaceName}");
        builder.AppendLine("# Auto-generated by containai-docker mode");
        builder.AppendLine($"# Generated at: {DateTime.UtcNow:yyyy-MM-ddTHH:mm:ssZ}");
        builder.AppendLine();
        builder.AppendLine($"Host {hostAlias}");
        builder.AppendLine("    HostName localhost");
        builder.AppendLine($"    Port {sshPort}");
        if (!string.IsNullOrWhiteSpace(remoteUser) && !string.Equals(remoteUser, "auto", StringComparison.Ordinal))
        {
            builder.AppendLine($"    User {remoteUser}");
        }

        builder.AppendLine("    StrictHostKeyChecking accept-new");
        builder.AppendLine("    UserKnownHostsFile ~/.ssh/containai.d/known_hosts");
        builder.AppendLine("    PreferredAuthentications publickey,keyboard-interactive");

        await File.WriteAllTextAsync(configFile, builder.ToString(), cancellationToken).ConfigureAwait(false);
        await stderr.WriteLineAsync($"SSH: ssh {hostAlias}").ConfigureAwait(false);
    }

    internal static bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings)
    {
        settings = FeatureSettings.Default;

        if (!File.Exists(configFile))
        {
            return false;
        }

        try
        {
            var raw = File.ReadAllText(configFile);
            var stripped = StripJsoncComments(raw);
            using var document = JsonDocument.Parse(stripped);
            if (!document.RootElement.TryGetProperty("features", out var features) || features.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            foreach (var feature in features.EnumerateObject())
            {
                if (!feature.Name.Contains("containai", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var featureElement = feature.Value;
                var dataVolume = DefaultDataVolume;
                if (featureElement.ValueKind == JsonValueKind.Object && featureElement.TryGetProperty("dataVolume", out var dataVolumeElement) && dataVolumeElement.ValueKind == JsonValueKind.String)
                {
                    var candidate = dataVolumeElement.GetString();
                    if (!string.IsNullOrWhiteSpace(candidate) && IsValidVolumeName(candidate!))
                    {
                        dataVolume = candidate!;
                    }
                }

                var enableCredentials = false;
                if (featureElement.ValueKind == JsonValueKind.Object && featureElement.TryGetProperty("enableCredentials", out var credentialsElement))
                {
                    enableCredentials = credentialsElement.ValueKind switch
                    {
                        JsonValueKind.True => true,
                        JsonValueKind.False => false,
                        JsonValueKind.String when bool.TryParse(credentialsElement.GetString(), out var parsed) => parsed,
                        _ => false,
                    };
                }

                var remoteUser = "vscode";
                if (featureElement.ValueKind == JsonValueKind.Object && featureElement.TryGetProperty("remoteUser", out var remoteUserElement) && remoteUserElement.ValueKind == JsonValueKind.String)
                {
                    var candidate = remoteUserElement.GetString();
                    if (!string.IsNullOrWhiteSpace(candidate) && !string.Equals(candidate, "auto", StringComparison.Ordinal) && UnixUsernameRegex().IsMatch(candidate!))
                    {
                        remoteUser = candidate!;
                    }
                }

                if (document.RootElement.TryGetProperty("remoteUser", out var topLevelRemoteUserElement) &&
                    topLevelRemoteUserElement.ValueKind == JsonValueKind.String)
                {
                    var candidate = topLevelRemoteUserElement.GetString();
                    if (!string.IsNullOrWhiteSpace(candidate) && !string.Equals(candidate, "auto", StringComparison.Ordinal) && UnixUsernameRegex().IsMatch(candidate!))
                    {
                        remoteUser = candidate!;
                    }
                }

                settings = new FeatureSettings(true, dataVolume, enableCredentials, remoteUser);
                return true;
            }

            return false;
        }
        catch (IOException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (UnauthorizedAccessException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (JsonException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (ArgumentException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (NotSupportedException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
    }

    internal static bool IsValidVolumeName(string volume)
    {
        if (!VolumeNameRegex().IsMatch(volume))
        {
            return false;
        }

        if (volume.Contains(':', StringComparison.Ordinal) ||
            volume.Contains('/', StringComparison.Ordinal) ||
            volume.Contains('~', StringComparison.Ordinal))
        {
            return false;
        }

        return !string.Equals(volume, ".", StringComparison.Ordinal) && !string.Equals(volume, "..", StringComparison.Ordinal);
    }

    private static string? GetFirstSubcommand(IReadOnlyList<string> args)
    {
        foreach (var arg in args)
        {
            if (!arg.StartsWith('-'))
            {
                return arg;
            }
        }

        return null;
    }

    private static string? GetContainerNameArg(IReadOnlyList<string> args, string subcommand)
    {
        var seenSubcommand = false;
        foreach (var arg in args)
        {
            if (!seenSubcommand)
            {
                if (string.Equals(arg, subcommand, StringComparison.Ordinal))
                {
                    seenSubcommand = true;
                }

                continue;
            }

            if (!arg.StartsWith('-'))
            {
                return arg;
            }
        }

        return null;
    }

    private static void ParseLabel(string labelToken, ref string? configFile, ref string? localFolder)
    {
        if (labelToken.StartsWith("devcontainer.config_file=", StringComparison.Ordinal))
        {
            configFile = labelToken[25..];
            return;
        }

        if (labelToken.StartsWith("devcontainer.local_folder=", StringComparison.Ordinal))
        {
            localFolder = labelToken[26..];
        }
    }

    private static List<string> PrependContext(string contextName, IReadOnlyList<string> args)
    {
        var dockerArgs = new List<string>(args.Count + 2)
        {
            "--context",
            contextName,
        };

        dockerArgs.AddRange(args);
        return dockerArgs;
    }

    private static (IReadOnlyList<string> DockerArgs, bool Verbose, bool Quiet) ParseWrapperFlags(IReadOnlyList<string> args)
    {
        var dockerArgs = new List<string>(args.Count);
        var verbose = false;
        var quiet = false;

        foreach (var arg in args)
        {
            if (string.Equals(arg, "--verbose", StringComparison.Ordinal))
            {
                verbose = true;
                continue;
            }

            if (string.Equals(arg, "--quiet", StringComparison.Ordinal))
            {
                quiet = true;
                continue;
            }

            dockerArgs.Add(arg);
        }

        return (dockerArgs, verbose, quiet);
    }

    private static async Task<T> WithPortLockAsync<T>(string lockPath, Func<Task<T>> action, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(lockPath)!);

        for (var attempt = 0; attempt < 100; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                await using var stream = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None).ConfigureAwait(false);
                return await action().ConfigureAwait(false);
            }
            catch (IOException)
            {
                await Task.Delay(100, cancellationToken).ConfigureAwait(false);
            }
        }

        return await action().ConfigureAwait(false);
    }

    private static async Task<int> RunDockerInteractiveAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo =
            {
                FileName = "docker",
                UseShellExecute = false,
            },
        };

        foreach (var arg in args)
        {
            process.StartInfo.ArgumentList.Add(arg);
        }

        try
        {
            if (!process.Start())
            {
                return 127;
            }
        }
        catch (Win32Exception ex)
        {
            await Console.Error.WriteLineAsync($"Failed to start 'docker': {ex.Message}").ConfigureAwait(false);
            return 127;
        }

        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return process.ExitCode;
    }

    private static async Task<ProcessResult> RunDockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo =
            {
                FileName = "docker",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            },
        };

        foreach (var arg in args)
        {
            process.StartInfo.ArgumentList.Add(arg);
        }

        try
        {
            if (!process.Start())
            {
                return new ProcessResult(127, string.Empty, "docker process failed to start");
            }
        }
        catch (Win32Exception ex)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
        catch (InvalidOperationException ex)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
        catch (NotSupportedException ex)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }

        var stdout = await process.StandardOutput.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
        var stderr = await process.StandardError.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return new ProcessResult(process.ExitCode, stdout, stderr);
    }

    private static IEnumerable<string> SplitLines(string text) => text
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(static value => !string.IsNullOrWhiteSpace(value));

    private static string ResolveHomeDirectory()
    {
        var home = Environment.GetEnvironmentVariable("HOME");
        if (!string.IsNullOrWhiteSpace(home))
        {
            return home!;
        }

        return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    }

    [GeneratedRegex("[^A-Za-z0-9._-]", RegexOptions.Compiled)]
    private static partial Regex NonWorkspaceCharacterRegex();

    [GeneratedRegex("-{2,}", RegexOptions.Compiled)]
    private static partial Regex MultiHyphenRegex();

    [GeneratedRegex("^[\\s]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][\\s]+[^#]*containai\\.d/", RegexOptions.Compiled)]
    private static partial Regex ContainAiIncludeRegex();

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex VolumeNameRegex();

    [GeneratedRegex("^[a-z_][a-z0-9_-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex UnixUsernameRegex();

    private static readonly HashSet<string> ContainerTargetingSubcommands =
    [
        "exec",
        "inspect",
        "start",
        "stop",
        "rm",
        "logs",
        "restart",
        "kill",
        "pause",
        "unpause",
        "port",
        "stats",
        "top",
    ];

    internal readonly record struct FeatureSettings(bool HasContainAiFeature, string DataVolume, bool EnableCredentials, string RemoteUser)
    {
        public static FeatureSettings Default => new(false, DefaultDataVolume, false, "vscode");
    }

    private readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);
}
