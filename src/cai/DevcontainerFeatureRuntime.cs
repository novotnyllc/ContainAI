using System.Net.NetworkInformation;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private const string DefaultDataVolume = "containai-data";
    private const string DefaultConfigPath = "/usr/local/share/containai/config.json";
    private const string DefaultLinkSpecPath = "/usr/local/lib/containai/link-spec.json";
    private const string DefaultDataDir = "/mnt/agent-data";
    private const string DefaultSshPidFile = "/var/run/sshd/containai-sshd.pid";
    private const string DefaultDockerPidFile = "/var/run/docker.pid";
    private const string DefaultDockerLogFile = "/var/log/containai-dockerd.log";


    private static readonly HashSet<string> CredentialTargets = new(StringComparer.Ordinal)
    {
        "/mnt/agent-data/config/gh/hosts.yml",
        "/mnt/agent-data/claude/credentials.json",
        "/mnt/agent-data/codex/config.toml",
        "/mnt/agent-data/codex/auth.json",
        "/mnt/agent-data/local/share/opencode/auth.json",
        "/mnt/agent-data/gemini/settings.json",
        "/mnt/agent-data/gemini/oauth_creds.json",
    };

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public DevcontainerFeatureRuntime(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
    }

    public async Task<int> RunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count == 0)
        {
            await stderr.WriteLineAsync("Usage: cai system devcontainer <install|init|start|verify-sysbox>").ConfigureAwait(false);
            return 1;
        }

        return args[0] switch
        {
            "install" => await RunInstallAsync(args.Skip(1).ToArray(), cancellationToken).ConfigureAwait(false),
            "init" => await RunInitAsync(cancellationToken).ConfigureAwait(false),
            "start" => await RunStartAsync(cancellationToken).ConfigureAwait(false),
            "verify-sysbox" => await RunVerifySysboxAsync(cancellationToken).ConfigureAwait(false),
            _ => await UnknownSubcommandAsync(args[0]).ConfigureAwait(false),
        };
    }

    private async Task<int> UnknownSubcommandAsync(string subcommand)
    {
        await stderr.WriteLineAsync($"Unknown devcontainer subcommand: {subcommand}").ConfigureAwait(false);
        await stderr.WriteLineAsync("Usage: cai system devcontainer <install|init|start|verify-sysbox>").ConfigureAwait(false);
        return 1;
    }

    private async Task<int> RunInstallAsync(string[] args, CancellationToken cancellationToken)
    {
        string? featureDirectory = null;
        for (var index = 0; index < args.Length; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--help":
                case "-h":
                    await stdout.WriteLineAsync("Usage: cai system devcontainer install [--feature-dir <path>]").ConfigureAwait(false);
                    return 0;
                case "--feature-dir":
                    if (!TryReadValue(args, ref index, out featureDirectory))
                    {
                        await stderr.WriteLineAsync("--feature-dir requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    break;
                default:
                    await stderr.WriteLineAsync($"Unknown install option: {token}").ConfigureAwait(false);
                    return 1;
            }
        }

        if (!TryParseFeatureBoolean("ENABLECREDENTIALS", defaultValue: false, out var enableCredentials, out var enableCredentialsError))
        {
            await stderr.WriteLineAsync(enableCredentialsError).ConfigureAwait(false);
            return 1;
        }

        if (!TryParseFeatureBoolean("ENABLESSH", defaultValue: true, out var enableSsh, out var enableSshError))
        {
            await stderr.WriteLineAsync(enableSshError).ConfigureAwait(false);
            return 1;
        }

        if (!TryParseFeatureBoolean("INSTALLDOCKER", defaultValue: true, out var installDocker, out var installDockerError))
        {
            await stderr.WriteLineAsync(installDockerError).ConfigureAwait(false);
            return 1;
        }

        var settings = new FeatureConfig(
            DataVolume: Environment.GetEnvironmentVariable("DATAVOLUME") ?? DefaultDataVolume,
            EnableCredentials: enableCredentials,
            EnableSsh: enableSsh,
            InstallDocker: installDocker,
            RemoteUser: Environment.GetEnvironmentVariable("REMOTEUSER") ?? "auto");

        if (!ValidateFeatureConfig(settings, out var validationError))
        {
            await stderr.WriteLineAsync(validationError).ConfigureAwait(false);
            return 1;
        }

        if (!await CommandExistsAsync("apt-get", cancellationToken).ConfigureAwait(false))
        {
            await stderr.WriteLineAsync("ContainAI feature requires Debian/Ubuntu image with apt-get.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("ContainAI: Installing feature...").ConfigureAwait(false);
        Directory.CreateDirectory("/usr/local/share/containai");
        Directory.CreateDirectory("/usr/local/lib/containai");

        var configJson = JsonSerializer.Serialize(
            settings,
            JsonContext.Default.FeatureConfig);
        await File.WriteAllTextAsync(DefaultConfigPath, configJson + Environment.NewLine, cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync("  Configuration saved").ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(featureDirectory))
        {
            var sourceLinkSpec = Path.Combine(featureDirectory, "link-spec.json");
            if (File.Exists(sourceLinkSpec))
            {
                File.Copy(sourceLinkSpec, DefaultLinkSpecPath, overwrite: true);
                await stdout.WriteLineAsync("  Installed: link-spec.json").ConfigureAwait(false);
            }
            else
            {
                await stdout.WriteLineAsync("  Note: link-spec.json not bundled - symlinks will be skipped").ConfigureAwait(false);
            }
        }

        await RunAsRootAsync("apt-get", ["update", "-qq"], cancellationToken).ConfigureAwait(false);

        if (settings.EnableSsh)
        {
            await RunAsRootAsync("apt-get", ["install", "-y", "-qq", "openssh-server"], cancellationToken).ConfigureAwait(false);
            await RunAsRootAsync("mkdir", ["-p", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: openssh-server").ConfigureAwait(false);
        }

        if (settings.InstallDocker)
        {
            await RunAsRootAsync("apt-get", ["install", "-y", "-qq", "curl", "ca-certificates"], cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: curl, ca-certificates").ConfigureAwait(false);
            await RunAsRootAsync("sh", ["-c", "curl -fsSL https://get.docker.com | sh"], cancellationToken).ConfigureAwait(false);
            await AddUserToDockerGroupIfPresentAsync("vscode", cancellationToken).ConfigureAwait(false);
            await AddUserToDockerGroupIfPresentAsync("node", cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: docker (DinD starts via postStartCommand)").ConfigureAwait(false);
        }

        await RunAsRootAsync("apt-get", ["clean"], cancellationToken).ConfigureAwait(false);
        await RunAsRootAsync("sh", ["-c", "rm -rf /var/lib/apt/lists/*"], cancellationToken).ConfigureAwait(false);

        await stdout.WriteLineAsync("ContainAI feature installed successfully").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Data volume: {settings.DataVolume}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Credentials: {settings.EnableCredentials}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  SSH: {settings.EnableSsh}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Docker: {settings.InstallDocker}").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunInitAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(DefaultConfigPath))
        {
            await stderr.WriteLineAsync($"ERROR: Configuration file not found: {DefaultConfigPath}").ConfigureAwait(false);
            return 1;
        }

        var settings = await LoadFeatureConfigAsync(DefaultConfigPath, cancellationToken).ConfigureAwait(false);
        if (settings is null)
        {
            await stderr.WriteLineAsync($"ERROR: Failed to parse configuration file: {DefaultConfigPath}").ConfigureAwait(false);
            return 1;
        }

        var verifyCode = await RunVerifySysboxAsync(cancellationToken).ConfigureAwait(false);
        if (verifyCode != 0)
        {
            return verifyCode;
        }

        var userHome = await DetectUserHomeAsync(settings.RemoteUser, cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync($"ContainAI init: Setting up symlinks in {userHome}").ConfigureAwait(false);

        if (!Directory.Exists(DefaultDataDir))
        {
            await stderr.WriteLineAsync($"Warning: Data volume not mounted at {DefaultDataDir}").ConfigureAwait(false);
            await stderr.WriteLineAsync("Run \"cai import\" on host, then rebuild container with dataVolume option").ConfigureAwait(false);
            return 0;
        }

        if (!File.Exists(DefaultLinkSpecPath))
        {
            await stderr.WriteLineAsync($"Warning: link-spec.json not found at {DefaultLinkSpecPath}").ConfigureAwait(false);
            await stderr.WriteLineAsync("Feature may not be fully installed").ConfigureAwait(false);
            return 0;
        }

        var linkSpecJson = await File.ReadAllTextAsync(DefaultLinkSpecPath, cancellationToken).ConfigureAwait(false);
        var linkSpec = JsonSerializer.Deserialize(linkSpecJson, JsonContext.Default.LinkSpecDocument);
        if (linkSpec?.Links is null || linkSpec.Links.Count == 0)
        {
            await stderr.WriteLineAsync("Warning: link-spec has no links").ConfigureAwait(false);
            return 0;
        }

        var created = 0;
        var skipped = 0;
        var sourceHome = string.IsNullOrWhiteSpace(linkSpec.HomeDirectory) ? "/home/agent" : linkSpec.HomeDirectory!;
        foreach (var link in linkSpec.Links)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (link is null || string.IsNullOrWhiteSpace(link.Link) || string.IsNullOrWhiteSpace(link.Target))
            {
                continue;
            }

            if (!settings.EnableCredentials && CredentialTargets.Contains(link.Target))
            {
                await stdout.WriteLineAsync($"  [SKIP] {link.Link} (credentials disabled)").ConfigureAwait(false);
                skipped++;
                continue;
            }

            if (!File.Exists(link.Target) && !Directory.Exists(link.Target))
            {
                continue;
            }

            var rewrittenLink = link.Link.StartsWith(sourceHome, StringComparison.Ordinal)
                ? userHome + link.Link[sourceHome.Length..]
                : link.Link;
            var parentDirectory = Path.GetDirectoryName(rewrittenLink);
            if (!string.IsNullOrWhiteSpace(parentDirectory))
            {
                Directory.CreateDirectory(parentDirectory);
            }

            var removeFirst = link.RemoveFirst ?? false;
            if (Directory.Exists(rewrittenLink) && !IsSymlink(rewrittenLink))
            {
                if (!removeFirst)
                {
                    await stderr.WriteLineAsync($"  [FAIL] {rewrittenLink} (directory exists, remove_first not set)").ConfigureAwait(false);
                    continue;
                }

                Directory.Delete(rewrittenLink, recursive: true);
            }
            else if (File.Exists(rewrittenLink) || IsSymlink(rewrittenLink))
            {
                File.Delete(rewrittenLink);
            }

            if (Directory.Exists(link.Target))
            {
                Directory.CreateSymbolicLink(rewrittenLink, link.Target);
            }
            else
            {
                File.CreateSymbolicLink(rewrittenLink, link.Target);
            }

            await stdout.WriteLineAsync($"  [OK] {rewrittenLink} -> {link.Target}").ConfigureAwait(false);
            created++;
        }

        await stdout.WriteAsync($"\nContainAI init complete: {created} symlinks created").ConfigureAwait(false);
        if (skipped > 0)
        {
            await stdout.WriteAsync($", {skipped} credential files skipped").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync().ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunStartAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(DefaultConfigPath))
        {
            await stderr.WriteLineAsync($"ERROR: Configuration file not found: {DefaultConfigPath}").ConfigureAwait(false);
            return 1;
        }

        var settings = await LoadFeatureConfigAsync(DefaultConfigPath, cancellationToken).ConfigureAwait(false);
        if (settings is null)
        {
            await stderr.WriteLineAsync($"ERROR: Failed to parse configuration file: {DefaultConfigPath}").ConfigureAwait(false);
            return 1;
        }

        var verifyCode = await RunVerifySysboxAsync(cancellationToken).ConfigureAwait(false);
        if (verifyCode != 0)
        {
            return verifyCode;
        }

        if (settings.EnableSsh)
        {
            var sshExit = await StartSshdAsync(cancellationToken).ConfigureAwait(false);
            if (sshExit != 0)
            {
                return sshExit;
            }
        }

        var dockerExit = await StartDockerdAsync(cancellationToken).ConfigureAwait(false);
        if (dockerExit != 0)
        {
            await stderr.WriteLineAsync("Warning: DinD not available").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync("[OK] ContainAI devcontainer ready").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunVerifySysboxAsync(CancellationToken cancellationToken)
    {
        var passed = 0;
        var sysboxfsFound = false;
        await stdout.WriteLineAsync("ContainAI Sysbox Verification").ConfigureAwait(false);
        await stdout.WriteLineAsync("--------------------------------").ConfigureAwait(false);

        if (await IsSysboxFsMountedAsync(cancellationToken).ConfigureAwait(false))
        {
            sysboxfsFound = true;
            passed++;
            await stdout.WriteLineAsync("  [OK] Sysboxfs: mounted (REQUIRED)").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync("  [FAIL] Sysboxfs: not found (REQUIRED)").ConfigureAwait(false);
        }

        if (await HasUidMappingIsolationAsync(cancellationToken).ConfigureAwait(false))
        {
            passed++;
            await stdout.WriteLineAsync("  [OK] UID mapping: sysbox user namespace").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync("  [FAIL] UID mapping: 0->0 (not sysbox)").ConfigureAwait(false);
        }

        if (await CommandSucceedsAsync("unshare", ["--user", "--map-root-user", "true"], cancellationToken).ConfigureAwait(false))
        {
            passed++;
            await stdout.WriteLineAsync("  [OK] Nested userns: allowed").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync("  [FAIL] Nested userns: blocked").ConfigureAwait(false);
        }

        var tempDirectory = Path.Combine(Path.GetTempPath(), $"containai-sysbox-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDirectory);
        var mountSucceeded = await CommandSucceedsAsync("mount", ["-t", "tmpfs", "none", tempDirectory], cancellationToken).ConfigureAwait(false);
        if (mountSucceeded)
        {
            _ = await CommandSucceedsAsync("umount", [tempDirectory], cancellationToken).ConfigureAwait(false);
            passed++;
            await stdout.WriteLineAsync("  [OK] Capabilities: CAP_SYS_ADMIN works").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync("  [FAIL] Capabilities: mount denied").ConfigureAwait(false);
        }

        try
        {
            Directory.Delete(tempDirectory, recursive: true);
        }
        catch (IOException ex)
        {
            // Ignore cleanup failures.
            _ = ex;
        }
        catch (UnauthorizedAccessException ex)
        {
            // Ignore cleanup failures.
            _ = ex;
        }

        await stdout.WriteLineAsync($"\nPassed: {passed} checks").ConfigureAwait(false);
        if (!sysboxfsFound || passed < 3)
        {
            await stderr.WriteLineAsync("FAIL: sysbox verification failed").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("[OK] Running in sysbox sandbox").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> StartSshdAsync(CancellationToken cancellationToken)
    {
        if (!await CommandExistsAsync("sshd", cancellationToken).ConfigureAwait(false))
        {
            await stderr.WriteLineAsync("Warning: sshd not installed").ConfigureAwait(false);
            return 0;
        }

        var sshPort = Environment.GetEnvironmentVariable("CONTAINAI_SSH_PORT") ?? "2322";
        if (await IsSshdRunningFromPidFileAsync(DefaultSshPidFile, cancellationToken).ConfigureAwait(false))
        {
            await stdout.WriteLineAsync($"[OK] sshd already running on port {sshPort} (validated via pidfile)").ConfigureAwait(false);
            return 0;
        }

        if (IsPortInUse(sshPort))
        {
            await stdout.WriteLineAsync($"[OK] sshd appears to be running on port {sshPort} (port in use)").ConfigureAwait(false);
            return 0;
        }

        if (File.Exists(DefaultSshPidFile))
        {
            await RunAsRootAsync("rm", ["-f", DefaultSshPidFile], cancellationToken).ConfigureAwait(false);
        }

        await RunAsRootAsync("mkdir", ["-p", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);
        await RunAsRootAsync("chmod", ["755", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);

        if (!File.Exists("/etc/ssh/ssh_host_rsa_key"))
        {
            await RunAsRootAsync("ssh-keygen", ["-A"], cancellationToken).ConfigureAwait(false);
        }

        await RunAsRootAsync("/usr/sbin/sshd", ["-p", sshPort, "-o", $"PidFile={DefaultSshPidFile}"], cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync($"[OK] sshd started on port {sshPort}").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> StartDockerdAsync(CancellationToken cancellationToken)
    {
        if (!await CommandExistsAsync("dockerd", cancellationToken).ConfigureAwait(false))
        {
            return 0;
        }

        if (File.Exists(DefaultDockerPidFile))
        {
            var pidRaw = await File.ReadAllTextAsync(DefaultDockerPidFile, cancellationToken).ConfigureAwait(false);
            if (int.TryParse(pidRaw.Trim(), out var existingPid) && IsProcessAlive(existingPid))
            {
                await stdout.WriteLineAsync($"[OK] dockerd already running (pid {existingPid})").ConfigureAwait(false);
                return 0;
            }

            await RunAsRootAsync("rm", ["-f", DefaultDockerPidFile], cancellationToken).ConfigureAwait(false);
        }

        if (await CommandSucceedsAsync("docker", ["info"], cancellationToken).ConfigureAwait(false))
        {
            await stdout.WriteLineAsync("[OK] dockerd already running (socket active)").ConfigureAwait(false);
            return 0;
        }

        await stdout.WriteLineAsync("Starting dockerd...").ConfigureAwait(false);
        await RunAsRootAsync("sh", ["-c", $"nohup dockerd --pidfile={DefaultDockerPidFile} > {DefaultDockerLogFile} 2>&1 &"], cancellationToken).ConfigureAwait(false);

        for (var attempt = 0; attempt < 30; attempt++)
        {
            if (await CommandSucceedsAsync("docker", ["info"], cancellationToken).ConfigureAwait(false))
            {
                await stdout.WriteLineAsync("[OK] dockerd started (DinD ready)").ConfigureAwait(false);
                return 0;
            }

            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken).ConfigureAwait(false);
        }

        await stderr.WriteLineAsync($"[FAIL] dockerd failed to start (see {DefaultDockerLogFile})").ConfigureAwait(false);
        return 1;
    }

    private static bool ValidateFeatureConfig(FeatureConfig config, out string error)
    {
        if (!VolumeNameRegex().IsMatch(config.DataVolume))
        {
            error = $"ERROR: Invalid dataVolume \"{config.DataVolume}\". Must be alphanumeric with ._- allowed.";
            return false;
        }

        if (!string.Equals(config.RemoteUser, "auto", StringComparison.Ordinal) && !UnixUsernameRegex().IsMatch(config.RemoteUser))
        {
            error = $"ERROR: Invalid remoteUser \"{config.RemoteUser}\". Must be \"auto\" or a valid Unix username.";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static bool TryParseFeatureBoolean(string name, bool defaultValue, out bool value, out string error)
    {
        var rawValue = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(rawValue))
        {
            value = defaultValue;
            error = string.Empty;
            return true;
        }

        switch (rawValue.Trim())
        {
            case "true":
            case "TRUE":
            case "True":
            case "1":
                value = true;
                error = string.Empty;
                return true;
            case "false":
            case "FALSE":
            case "False":
            case "0":
                value = false;
                error = string.Empty;
                return true;
            default:
                value = defaultValue;
                error = $"ERROR: Invalid {name} \"{rawValue}\". Must be true or false.";
                return false;
        }
    }

    private static bool IsSymlink(string path)
    {
        try
        {
            var attributes = File.GetAttributes(path);
            return (attributes & FileAttributes.ReparsePoint) != 0;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }

    }

    private static bool IsProcessAlive(int processId)
    {
        if (processId <= 0)
        {
            return false;
        }

        try
        {
            if (OperatingSystem.IsLinux() && Directory.Exists($"/proc/{processId}"))
            {
                return true;
            }

            if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS())
            {
                var result = CliWrapProcessRunner
                    .RunCaptureAsync("kill", ["-0", processId.ToString(System.Globalization.CultureInfo.InvariantCulture)], CancellationToken.None)
                    .GetAwaiter()
                    .GetResult();
                return result.ExitCode == 0;
            }
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (IOException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }

        return false;
    }

    private static bool IsPortInUse(string portValue)
    {
        if (!int.TryParse(portValue, out var port))
        {
            return false;
        }

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

    private static async Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken)
    {
        if (!File.Exists(pidFilePath))
        {
            return false;
        }

        var pidRaw = await File.ReadAllTextAsync(pidFilePath, cancellationToken).ConfigureAwait(false);
        if (!int.TryParse(pidRaw.Trim(), out var pid))
        {
            return false;
        }

        if (!Directory.Exists($"/proc/{pid}"))
        {
            return false;
        }

        var commPath = $"/proc/{pid}/comm";
        if (File.Exists(commPath))
        {
            var comm = (await File.ReadAllTextAsync(commPath, cancellationToken).ConfigureAwait(false)).Trim();
            return string.Equals(comm, "sshd", StringComparison.Ordinal);
        }

        return IsProcessAlive(pid);
    }

    private static async Task<string> DetectUserHomeAsync(string remoteUser, CancellationToken cancellationToken)
    {
        var candidate = remoteUser;
        if (string.Equals(candidate, "auto", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(candidate))
        {
            candidate = await UserExistsAsync("vscode", cancellationToken).ConfigureAwait(false) ? "vscode"
                : await UserExistsAsync("node", cancellationToken).ConfigureAwait(false) ? "node"
                : Environment.GetEnvironmentVariable("USER") ?? "root";
        }

        if (await CommandExistsAsync("getent", cancellationToken).ConfigureAwait(false))
        {
            var result = await RunProcessCaptureAsync("getent", ["passwd", candidate], cancellationToken).ConfigureAwait(false);
            if (result.ExitCode == 0)
            {
                var parts = result.StandardOutput.Trim().Split(':');
                if (parts.Length >= 6 && Directory.Exists(parts[5]))
                {
                    return parts[5];
                }
            }
        }

        if (string.Equals(candidate, "root", StringComparison.Ordinal))
        {
            return "/root";
        }

        var conventionalPath = $"/home/{candidate}";
        if (Directory.Exists(conventionalPath))
        {
            return conventionalPath;
        }

        return Environment.GetEnvironmentVariable("HOME") ?? conventionalPath;
    }

    private static async Task<bool> UserExistsAsync(string user, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync("id", ["-u", user], cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private async Task AddUserToDockerGroupIfPresentAsync(string user, CancellationToken cancellationToken)
    {
        if (!await UserExistsAsync(user, cancellationToken).ConfigureAwait(false))
        {
            return;
        }

        await RunAsRootAsync("usermod", ["-aG", "docker", user], cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync($"    Added {user} to docker group").ConfigureAwait(false);
    }

    private static async Task<FeatureConfig?> LoadFeatureConfigAsync(string path, CancellationToken cancellationToken)
    {
        try
        {
            var json = await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
            return JsonSerializer.Deserialize(json, JsonContext.Default.FeatureConfig);
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
    }

    private static async Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists("/proc/mounts"))
        {
            return false;
        }

        var mounts = await File.ReadAllLinesAsync("/proc/mounts", cancellationToken).ConfigureAwait(false);
        foreach (var line in mounts)
        {
            var fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (fields.Length >= 3 &&
                (string.Equals(fields[2], "sysboxfs", StringComparison.Ordinal) ||
                 string.Equals(fields[2], "fuse.sysboxfs", StringComparison.Ordinal)))
            {
                return true;
            }
        }

        return false;
    }

    private static async Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists("/proc/self/uid_map"))
        {
            return false;
        }

        var lines = await File.ReadAllLinesAsync("/proc/self/uid_map", cancellationToken).ConfigureAwait(false);
        foreach (var line in lines)
        {
            var fields = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length >= 3 && fields[0] == "0")
            {
                return fields[1] != "0";
            }
        }

        return false;
    }

    private static bool TryReadValue(string[] args, ref int index, out string value)
    {
        value = string.Empty;
        if (index + 1 >= args.Length)
        {
            return false;
        }

        index++;
        value = args[index];
        return true;
    }

    private static async Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync("sh", ["-c", $"command -v {command} >/dev/null 2>&1"], cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private static async Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private static async Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        if (IsRunningAsRoot())
        {
            var direct = await RunProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
            if (direct.ExitCode != 0)
            {
                throw new InvalidOperationException(direct.StandardError.Trim());
            }

            return;
        }

        if (!await CommandSucceedsAsync("sudo", ["-n", "true"], cancellationToken).ConfigureAwait(false))
        {
            throw new InvalidOperationException($"Root privileges required for command: {executable}");
        }

        var sudoArgs = new List<string>(arguments.Count + 2) { "-n", executable };
        foreach (var argument in arguments)
        {
            sudoArgs.Add(argument);
        }

        var sudoResult = await RunProcessCaptureAsync("sudo", sudoArgs, cancellationToken).ConfigureAwait(false);
        if (sudoResult.ExitCode != 0)
        {
            throw new InvalidOperationException(sudoResult.StandardError.Trim());
        }
    }

    private static bool IsRunningAsRoot() => string.Equals(Environment.UserName, "root", StringComparison.Ordinal);

    private static async Task<ProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await CliWrapProcessRunner.RunCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
        return new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    private readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex VolumeNameRegex();

    [GeneratedRegex("^[a-z_][a-z0-9_-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex UnixUsernameRegex();

    [JsonSerializable(typeof(FeatureConfig))]
    [JsonSerializable(typeof(LinkSpecDocument))]
    private partial class JsonContext : JsonSerializerContext;

    internal sealed record FeatureConfig(
        [property: JsonPropertyName("data_volume")] string DataVolume,
        [property: JsonPropertyName("enable_credentials")] bool EnableCredentials,
        [property: JsonPropertyName("enable_ssh")] bool EnableSsh,
        [property: JsonPropertyName("install_docker")] bool InstallDocker,
        [property: JsonPropertyName("remote_user")] string RemoteUser);

    internal sealed record LinkSpecDocument(
        [property: JsonPropertyName("home_dir")] string? HomeDirectory,
        [property: JsonPropertyName("links")] IReadOnlyList<LinkEntry>? Links);

    internal sealed record LinkEntry(
        [property: JsonPropertyName("link")] string Link,
        [property: JsonPropertyName("target")] string Target,
        [property: JsonPropertyName("remove_first")] bool? RemoveFirst);
}
