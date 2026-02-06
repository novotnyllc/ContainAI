using System.Diagnostics;
using System.Reflection;
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
    private readonly NativeSessionCommandRuntime _sessionRuntime;

    public NativeLifecycleCommandRuntime(TextWriter? stdout = null, TextWriter? stderr = null)
    {
        _stdout = stdout ?? Console.Out;
        _stderr = stderr ?? Console.Error;
        _sessionRuntime = new NativeSessionCommandRuntime(_stdout, _stderr);
    }

    public Task<int> RunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count == 0)
        {
            return Task.FromResult(1);
        }

        return args[0] switch
        {
            "run" => _sessionRuntime.RunRunAsync(args, cancellationToken),
            "shell" => _sessionRuntime.RunShellAsync(args, cancellationToken),
            "exec" => _sessionRuntime.RunExecAsync(args, cancellationToken),
            "help" => RunHelpAsync(args, cancellationToken),
            "version" => RunVersionAsync(args, cancellationToken),
            "doctor" => RunDoctorAsync(args, cancellationToken),
            "validate" => RunValidateAsync(args, cancellationToken),
            "setup" => RunSetupAsync(args, cancellationToken),
            "import" => RunImportAsync(args, cancellationToken),
            "export" => RunExportAsync(args, cancellationToken),
            "sync" => RunSyncAsync(args, cancellationToken),
            "links" => RunLinksAsync(args, cancellationToken),
            "update" => RunUpdateAsync(args, cancellationToken),
            "refresh" => RunRefreshAsync(args, cancellationToken),
            "uninstall" => RunUninstallAsync(args, cancellationToken),
            "completion" => RunCompletionAsync(args, cancellationToken),
            "config" => RunConfigAsync(args, cancellationToken),
            "template" => RunTemplateAsync(args, cancellationToken),
            "ssh" => RunSshAsync(args, cancellationToken),
            "stop" => RunStopAsync(args, cancellationToken),
            "gc" => RunGcAsync(args, cancellationToken),
            _ => Task.FromResult(1),
        };
    }

    private async Task<int> RunHelpAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (args.Count <= 1)
        {
            await _stdout.WriteLineAsync(GetRootHelpText()).ConfigureAwait(false);
            return 0;
        }

        var topic = args[1];
        return topic switch
        {
            "config" => await WriteUsageAsync("Usage: cai config <list|get|set|unset> [options]").ConfigureAwait(false),
            "template" => await WriteUsageAsync("Usage: cai template upgrade [name] [--dry-run]").ConfigureAwait(false),
            "ssh" => await WriteUsageAsync("Usage: cai ssh cleanup [--dry-run]").ConfigureAwait(false),
            "completion" => await WriteUsageAsync("Usage: cai completion <bash|zsh>").ConfigureAwait(false),
            "links" => await WriteUsageAsync("Usage: cai links <check|fix> [--name <container>] [--workspace <path>] [--dry-run]").ConfigureAwait(false),
            _ => await WriteUsageAsync(GetRootHelpText()).ConfigureAwait(false),
        };
    }

    private Task<int> WriteUsageAsync(string usage)
    {
        _stdout.WriteLine(usage);
        return Task.FromResult(0);
    }

    private async Task<int> RunVersionAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var json = args.Contains("--json", StringComparer.Ordinal);
        var (version, installType, installDir) = ResolveVersionInfo();

        if (json)
        {
            await _stdout.WriteLineAsync($"{{\"version\":\"{version}\",\"install_type\":\"{installType}\",\"install_dir\":\"{EscapeJson(installDir)}\"}}").ConfigureAwait(false);
            return 0;
        }

        await _stdout.WriteLineAsync(version).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunDoctorAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var outputJson = args.Contains("--json", StringComparer.Ordinal);
        var dockerCli = await CommandSucceedsAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false);
        var contextName = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var contextExists = !string.IsNullOrWhiteSpace(contextName);
        var dockerInfoArgs = new List<string>();
        if (contextExists)
        {
            dockerInfoArgs.Add("--context");
            dockerInfoArgs.Add(contextName!);
        }

        dockerInfoArgs.Add("info");
        var dockerInfo = await CommandSucceedsAsync("docker", dockerInfoArgs, cancellationToken).ConfigureAwait(false);

        var runtimeArgs = new List<string>(dockerInfoArgs)
        {
            "--format",
            "{{json .Runtimes}}",
        };
        var runtimeInfo = await RunProcessCaptureAsync("docker", runtimeArgs, cancellationToken).ConfigureAwait(false);
        var sysboxRuntime = runtimeInfo.ExitCode == 0 && runtimeInfo.StandardOutput.Contains("sysbox-runc", StringComparison.Ordinal);

        if (outputJson)
        {
            await _stdout.WriteLineAsync($"{{\"docker_cli\":{dockerCli.ToString().ToLowerInvariant()},\"context\":{contextExists.ToString().ToLowerInvariant()},\"docker_daemon\":{dockerInfo.ToString().ToLowerInvariant()},\"sysbox_runtime\":{sysboxRuntime.ToString().ToLowerInvariant()}}}").ConfigureAwait(false);
        }
        else
        {
            await _stdout.WriteLineAsync($"Docker CLI: {(dockerCli ? "ok" : "missing")}").ConfigureAwait(false);
            await _stdout.WriteLineAsync($"Context: {(contextExists ? contextName : "missing")}").ConfigureAwait(false);
            await _stdout.WriteLineAsync($"Docker daemon: {(dockerInfo ? "ok" : "unreachable")}").ConfigureAwait(false);
            await _stdout.WriteLineAsync($"sysbox-runc runtime: {(sysboxRuntime ? "ok" : "missing")}").ConfigureAwait(false);
        }

        return dockerCli && contextExists && dockerInfo && sysboxRuntime ? 0 : 1;
    }

    private async Task<int> RunValidateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var doctorArgs = args.Contains("--json", StringComparer.Ordinal)
            ? new[] { "doctor", "--json" }
            : new[] { "doctor" };
        return await RunDoctorAsync(doctorArgs, cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunSetupAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
        var verbose = args.Contains("--verbose", StringComparer.Ordinal);
        var home = ResolveHomeDirectory();
        var containAiDir = Path.Combine(home, ".config", "containai");
        var sshDir = Path.Combine(home, ".ssh", "containai.d");
        var sshKeyPath = Path.Combine(containAiDir, "id_containai");
        var socketPath = "/var/run/containai-docker.sock";

        if (dryRun)
        {
            await _stdout.WriteLineAsync($"Would create {containAiDir}").ConfigureAwait(false);
            await _stdout.WriteLineAsync($"Would create {sshDir}").ConfigureAwait(false);
            await _stdout.WriteLineAsync($"Would generate SSH key {sshKeyPath}").ConfigureAwait(false);
            await _stdout.WriteLineAsync($"Would verify runtime socket {socketPath}").ConfigureAwait(false);
            await _stdout.WriteLineAsync("Would create Docker context containai-docker").ConfigureAwait(false);
            return 0;
        }

        if (!await CommandSucceedsAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false))
        {
            await _stderr.WriteLineAsync("Docker CLI is required for setup.").ConfigureAwait(false);
            return 1;
        }

        Directory.CreateDirectory(containAiDir);
        Directory.CreateDirectory(sshDir);

        if (!File.Exists(sshKeyPath))
        {
            var keygen = await RunProcessCaptureAsync(
                "ssh-keygen",
                ["-t", "ed25519", "-N", string.Empty, "-f", sshKeyPath, "-C", "containai"],
                cancellationToken).ConfigureAwait(false);
            if (keygen.ExitCode != 0)
            {
                await _stderr.WriteLineAsync(keygen.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        if (!File.Exists(socketPath))
        {
            if (await CommandSucceedsAsync("systemctl", ["cat", "containai-docker.service"], cancellationToken).ConfigureAwait(false))
            {
                await RunProcessCaptureAsync("systemctl", ["start", "containai-docker.service"], cancellationToken).ConfigureAwait(false);
            }
        }

        if (!File.Exists(socketPath) && OperatingSystem.IsMacOS())
        {
            await RunProcessCaptureAsync("limactl", ["start", "containai"], cancellationToken).ConfigureAwait(false);
        }

        if (File.Exists(socketPath))
        {
            var createContext = await RunProcessCaptureAsync(
                "docker",
                ["context", "create", "containai-docker", "--docker", $"host=unix://{socketPath}"],
                cancellationToken).ConfigureAwait(false);
            if (createContext.ExitCode != 0 && verbose)
            {
                var error = createContext.StandardError.Trim();
                if (!string.IsNullOrWhiteSpace(error))
                {
                    await _stderr.WriteLineAsync(error).ConfigureAwait(false);
                }
            }
        }
        else
        {
            await _stderr.WriteLineAsync($"Setup warning: runtime socket not found at {socketPath}.").ConfigureAwait(false);
        }

        var doctorExitCode = await RunDoctorAsync(["doctor"], cancellationToken).ConfigureAwait(false);
        if (doctorExitCode != 0)
        {
            await _stderr.WriteLineAsync("Setup completed with warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await _stdout.WriteLineAsync("Setup complete.").ConfigureAwait(false);
        return doctorExitCode;
    }

    private async Task<int> RunImportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var source = GetOptionValue(args, "--from");
        var explicitVolume = GetOptionValue(args, "--data-volume");
        var workspace = GetOptionValue(args, "--workspace") ?? Directory.GetCurrentDirectory();
        var volume = await ResolveDataVolumeAsync(workspace, explicitVolume, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            await _stderr.WriteLineAsync("Unable to resolve data volume. Use --data-volume.").ConfigureAwait(false);
            return 1;
        }

        var sourcePath = string.IsNullOrWhiteSpace(source) ? ResolveHomeDirectory() : ExpandHomePath(source);
        if (!File.Exists(sourcePath) && !Directory.Exists(sourcePath))
        {
            await _stderr.WriteLineAsync($"Import source not found: {sourcePath}").ConfigureAwait(false);
            return 1;
        }

        if (sourcePath.EndsWith(".tgz", StringComparison.OrdinalIgnoreCase))
        {
            var archiveDir = Path.GetDirectoryName(Path.GetFullPath(sourcePath))!;
            var archiveName = Path.GetFileName(sourcePath);
            var restore = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "-v", $"{archiveDir}:/backup:ro", "alpine:3.20", "sh", "-lc", $"tar -xzf /backup/{archiveName} -C /mnt/agent-data"],
                cancellationToken).ConfigureAwait(false);
            if (restore.ExitCode != 0)
            {
                await _stderr.WriteLineAsync(restore.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }
        else
        {
            var sourceFull = Path.GetFullPath(sourcePath);
            var import = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "-v", $"{sourceFull}:/src:ro", "alpine:3.20", "sh", "-lc", "cp -a /src/. /mnt/agent-data/"],
                cancellationToken).ConfigureAwait(false);
            if (import.ExitCode != 0)
            {
                await _stderr.WriteLineAsync(import.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        await _stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunExportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var output = GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o");
        var explicitVolume = GetOptionValue(args, "--data-volume");
        var container = GetOptionValue(args, "--container");
        var workspace = GetOptionValue(args, "--workspace") ?? Directory.GetCurrentDirectory();
        var volume = string.IsNullOrWhiteSpace(container)
            ? await ResolveDataVolumeAsync(workspace, explicitVolume, cancellationToken).ConfigureAwait(false)
            : await ResolveDataVolumeFromContainerAsync(container, explicitVolume, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            await _stderr.WriteLineAsync("Unable to resolve data volume. Use --data-volume.").ConfigureAwait(false);
            return 1;
        }

        var outputPath = string.IsNullOrWhiteSpace(output)
            ? Path.Combine(Directory.GetCurrentDirectory(), $"containai-export-{DateTime.UtcNow:yyyyMMdd-HHmmss}.tgz")
            : Path.GetFullPath(ExpandHomePath(output));

        if (Directory.Exists(outputPath))
        {
            outputPath = Path.Combine(outputPath, $"containai-export-{DateTime.UtcNow:yyyyMMdd-HHmmss}.tgz");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var outputDir = Path.GetDirectoryName(outputPath)!;
        var outputFile = Path.GetFileName(outputPath);

        var exportResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "-v", $"{outputDir}:/out", "alpine:3.20", "sh", "-lc", $"tar -C /mnt/agent-data -czf /out/{outputFile} ."],
            cancellationToken).ConfigureAwait(false);
        if (exportResult.ExitCode != 0)
        {
            await _stderr.WriteLineAsync(exportResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await _stdout.WriteLineAsync(outputPath).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunSyncAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var sourceRoot = ResolveHomeDirectory();
        var destinationRoot = "/mnt/agent-data";
        if (!Directory.Exists(destinationRoot))
        {
            await _stderr.WriteLineAsync("sync must run inside a container with /mnt/agent-data").ConfigureAwait(false);
            return 1;
        }

        foreach (var directory in new[] { ".config", ".ssh", ".claude", ".codex" })
        {
            var source = Path.Combine(sourceRoot, directory);
            var destination = Path.Combine(destinationRoot, directory);
            if (!Directory.Exists(source))
            {
                continue;
            }

            Directory.CreateDirectory(destination);
            await CopyDirectoryAsync(source, destination, cancellationToken).ConfigureAwait(false);
        }

        await _stdout.WriteLineAsync("Sync complete.").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunLinksAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2 || args[1] is "-h" or "--help")
        {
            await _stdout.WriteLineAsync("Usage: cai links <check|fix> [--name <container>] [--workspace <path>] [--dry-run] [--quiet]").ConfigureAwait(false);
            return 0;
        }

        var subcommand = args[1];
        if (!string.Equals(subcommand, "check", StringComparison.Ordinal) &&
            !string.Equals(subcommand, "fix", StringComparison.Ordinal))
        {
            await _stderr.WriteLineAsync($"Unknown links subcommand: {subcommand}").ConfigureAwait(false);
            return 1;
        }

        string? containerName = null;
        string? workspace = null;
        var dryRun = false;
        var quiet = false;

        for (var index = 2; index < args.Count; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--name":
                case "--container":
                    if (index + 1 >= args.Count)
                    {
                        await _stderr.WriteLineAsync($"{token} requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    containerName = args[++index];
                    break;
                case "--workspace":
                    if (index + 1 >= args.Count)
                    {
                        await _stderr.WriteLineAsync("--workspace requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    workspace = args[++index];
                    break;
                case "--dry-run":
                    dryRun = true;
                    break;
                case "--quiet":
                case "-q":
                    quiet = true;
                    break;
                case "--verbose":
                case "--config":
                    if (token == "--config" && index + 1 < args.Count)
                    {
                        index++;
                    }
                    break;
                case "-h":
                case "--help":
                    await _stdout.WriteLineAsync("Usage: cai links <check|fix> [--name <container>] [--workspace <path>] [--dry-run] [--quiet]").ConfigureAwait(false);
                    return 0;
                default:
                    if (!token.StartsWith("-", StringComparison.Ordinal) && string.IsNullOrWhiteSpace(workspace))
                    {
                        workspace = token;
                    }
                    else if (!string.Equals(token, "--", StringComparison.Ordinal))
                    {
                        await _stderr.WriteLineAsync($"Unknown links option: {token}").ConfigureAwait(false);
                        return 1;
                    }

                    break;
            }
        }

        var resolvedWorkspace = string.IsNullOrWhiteSpace(workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(ExpandHomePath(workspace));

        if (string.IsNullOrWhiteSpace(containerName))
        {
            containerName = await ResolveWorkspaceContainerNameAsync(resolvedWorkspace, cancellationToken).ConfigureAwait(false);
        }

        if (string.IsNullOrWhiteSpace(containerName))
        {
            await _stderr.WriteLineAsync($"Unable to resolve container for workspace: {resolvedWorkspace}").ConfigureAwait(false);
            return 1;
        }

        var stateResult = await DockerCaptureAsync(
            ["inspect", "--format", "{{.State.Status}}", containerName],
            cancellationToken).ConfigureAwait(false);

        if (stateResult.ExitCode != 0)
        {
            await _stderr.WriteLineAsync($"Container not found: {containerName}").ConfigureAwait(false);
            return 1;
        }

        var state = stateResult.StandardOutput.Trim();
        if (string.Equals(subcommand, "check", StringComparison.Ordinal))
        {
            if (!string.Equals(state, "running", StringComparison.Ordinal))
            {
                await _stderr.WriteLineAsync($"Container '{containerName}' is not running (state: {state}).").ConfigureAwait(false);
                return 1;
            }
        }
        else if (!string.Equals(state, "running", StringComparison.Ordinal))
        {
            var startResult = await DockerCaptureAsync(["start", containerName], cancellationToken).ConfigureAwait(false);
            if (startResult.ExitCode != 0)
            {
                await _stderr.WriteLineAsync($"Failed to start container '{containerName}': {startResult.StandardError.Trim()}").ConfigureAwait(false);
                return 1;
            }
        }

        var command = new List<string>
        {
            "exec",
            containerName,
            "/usr/local/lib/containai/link-repair.sh",
        };

        if (string.Equals(subcommand, "check", StringComparison.Ordinal))
        {
            command.Add("--check");
        }
        else if (dryRun)
        {
            command.Add("--dry-run");
        }
        else
        {
            command.Add("--fix");
        }

        if (quiet)
        {
            command.Add("--quiet");
        }

        var runResult = await DockerCaptureAsync(command, cancellationToken).ConfigureAwait(false);
        if (!quiet)
        {
            var output = runResult.StandardOutput.Trim();
            if (!string.IsNullOrWhiteSpace(output))
            {
                await _stdout.WriteLineAsync(output).ConfigureAwait(false);
            }
        }

        if (runResult.ExitCode != 0)
        {
            var error = runResult.StandardError.Trim();
            if (!string.IsNullOrWhiteSpace(error))
            {
                await _stderr.WriteLineAsync(error).ConfigureAwait(false);
            }
        }

        return runResult.ExitCode;
    }

    private async Task<int> RunUpdateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
        var stopContainers = args.Contains("--stop-containers", StringComparer.Ordinal) || args.Contains("--force", StringComparer.Ordinal);
        var limaRecreate = args.Contains("--lima-recreate", StringComparer.Ordinal);
        var showHelp = args.Contains("--help", StringComparer.Ordinal) || args.Contains("-h", StringComparer.Ordinal);
        if (showHelp)
        {
            await _stdout.WriteLineAsync("Usage: cai update [--dry-run] [--stop-containers] [--force] [--lima-recreate]").ConfigureAwait(false);
            return 0;
        }

        if (!ValidateOptions(args, 1, "--dry-run", "--stop-containers", "--force", "--lima-recreate", "--verbose", "--help", "-h"))
        {
            await _stderr.WriteLineAsync("Unknown update option. Use 'cai update --help'.").ConfigureAwait(false);
            return 1;
        }

        if (dryRun)
        {
            await _stdout.WriteLineAsync("Would pull latest base image for configured channel.").ConfigureAwait(false);
            if (stopContainers)
            {
                await _stdout.WriteLineAsync("Would stop running ContainAI containers before update.").ConfigureAwait(false);
            }
            if (limaRecreate)
            {
                await _stdout.WriteLineAsync("Would recreate Lima VM 'containai'.").ConfigureAwait(false);
            }

            await _stdout.WriteLineAsync("Would refresh templates and verify installation.").ConfigureAwait(false);
            return 0;
        }

        if (limaRecreate && !OperatingSystem.IsMacOS())
        {
            await _stderr.WriteLineAsync("--lima-recreate is only supported on macOS.").ConfigureAwait(false);
            return 1;
        }

        if (limaRecreate)
        {
            await _stdout.WriteLineAsync("Recreating Lima VM 'containai'...").ConfigureAwait(false);
            await RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
            var start = await RunProcessCaptureAsync("limactl", ["start", "containai"], cancellationToken).ConfigureAwait(false);
            if (start.ExitCode != 0)
            {
                await _stderr.WriteLineAsync(start.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        if (stopContainers)
        {
            var stopResult = await DockerCaptureAsync(
                ["ps", "-q", "--filter", "label=containai.managed=true"],
                cancellationToken).ConfigureAwait(false);

            if (stopResult.ExitCode == 0)
            {
                foreach (var containerId in stopResult.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    await DockerCaptureAsync(["stop", containerId], cancellationToken).ConfigureAwait(false);
                }
            }
        }

        var refreshCode = await RunRefreshAsync(["refresh", "--rebuild"], cancellationToken).ConfigureAwait(false);
        if (refreshCode != 0)
        {
            return refreshCode;
        }

        var doctorCode = await RunDoctorAsync(["doctor"], cancellationToken).ConfigureAwait(false);
        if (doctorCode != 0)
        {
            await _stderr.WriteLineAsync("Update completed with validation warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await _stdout.WriteLineAsync("Update complete.").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunRefreshAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var showHelp = args.Contains("--help", StringComparer.Ordinal) || args.Contains("-h", StringComparer.Ordinal);
        if (showHelp)
        {
            await _stdout.WriteLineAsync("Usage: cai refresh [--rebuild] [--verbose]").ConfigureAwait(false);
            return 0;
        }

        if (!ValidateOptions(args, 1, "--rebuild", "--verbose", "--help", "-h"))
        {
            await _stderr.WriteLineAsync("Unknown refresh option. Use 'cai refresh --help'.").ConfigureAwait(false);
            return 1;
        }

        var channel = await ResolveChannelAsync(cancellationToken).ConfigureAwait(false);
        var baseImage = string.Equals(channel, "nightly", StringComparison.Ordinal)
            ? "ghcr.io/novotnyllc/containai:nightly"
            : "ghcr.io/novotnyllc/containai:latest";

        await _stdout.WriteLineAsync($"Pulling {baseImage}...").ConfigureAwait(false);
        var pull = await DockerCaptureAsync(["pull", baseImage], cancellationToken).ConfigureAwait(false);
        if (pull.ExitCode != 0)
        {
            await _stderr.WriteLineAsync(pull.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        if (!args.Contains("--rebuild", StringComparer.Ordinal))
        {
            await _stdout.WriteLineAsync("Refresh complete.").ConfigureAwait(false);
            return 0;
        }

        var templatesRoot = ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            await _stderr.WriteLineAsync($"Template directory not found: {templatesRoot}").ConfigureAwait(false);
            return 1;
        }

        var failures = 0;
        foreach (var templateDir in Directory.EnumerateDirectories(templatesRoot))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var templateName = Path.GetFileName(templateDir);
            var dockerfile = Path.Combine(templateDir, "Dockerfile");
            if (!File.Exists(dockerfile))
            {
                continue;
            }

            var imageName = $"containai-template-{templateName}:local";
            var build = await DockerCaptureAsync(
                [
                    "build",
                    "--build-arg", $"BASE_IMAGE={baseImage}",
                    "-t", imageName,
                    "-f", dockerfile,
                    templateDir,
                ],
                cancellationToken).ConfigureAwait(false);

            if (build.ExitCode != 0)
            {
                failures++;
                await _stderr.WriteLineAsync($"Template rebuild failed for '{templateName}': {build.StandardError.Trim()}").ConfigureAwait(false);
                continue;
            }

            await _stdout.WriteLineAsync($"Rebuilt template '{templateName}' as {imageName}").ConfigureAwait(false);
        }

        return failures == 0 ? 0 : 1;
    }

    private async Task<int> RunUninstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var showHelp = args.Contains("--help", StringComparer.Ordinal) || args.Contains("-h", StringComparer.Ordinal);
        if (showHelp)
        {
            await _stdout.WriteLineAsync("Usage: cai uninstall [--dry-run] [--containers] [--volumes] [--force]").ConfigureAwait(false);
            return 0;
        }

        if (!ValidateOptions(args, 1, "--dry-run", "--containers", "--volumes", "--force", "--verbose", "--help", "-h"))
        {
            await _stderr.WriteLineAsync("Unknown uninstall option. Use 'cai uninstall --help'.").ConfigureAwait(false);
            return 1;
        }

        var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
        var removeContainers = args.Contains("--containers", StringComparer.Ordinal);
        var removeVolumes = args.Contains("--volumes", StringComparer.Ordinal);

        var contextsToRemove = new[] { "containai-docker", "containai-secure", "docker-containai" };
        foreach (var context in contextsToRemove)
        {
            if (dryRun)
            {
                await _stdout.WriteLineAsync($"Would remove Docker context: {context}").ConfigureAwait(false);
                continue;
            }

            await DockerCaptureAsync(["context", "rm", "-f", context], cancellationToken).ConfigureAwait(false);
        }

        if (!removeContainers)
        {
            await _stdout.WriteLineAsync("Uninstall complete (contexts cleaned). Use --containers/--volumes for full cleanup.").ConfigureAwait(false);
            return 0;
        }

        var list = await DockerCaptureAsync(["ps", "-aq", "--filter", "label=containai.managed=true"], cancellationToken).ConfigureAwait(false);
        if (list.ExitCode != 0)
        {
            await _stderr.WriteLineAsync(list.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        var containerIds = list.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var volumeNames = new HashSet<string>(StringComparer.Ordinal);
        foreach (var containerId in containerIds)
        {
            if (dryRun)
            {
                await _stdout.WriteLineAsync($"Would remove container {containerId}").ConfigureAwait(false);
            }
            else
            {
                await DockerCaptureAsync(["rm", "-f", containerId], cancellationToken).ConfigureAwait(false);
            }

            if (!removeVolumes)
            {
                continue;
            }

            var inspect = await DockerCaptureAsync(
                ["inspect", "--format", "{{range .Mounts}}{{if and (eq .Type \"volume\") (eq .Destination \"/mnt/agent-data\")}}{{.Name}}{{end}}{{end}}", containerId],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                var volumeName = inspect.StandardOutput.Trim();
                if (!string.IsNullOrWhiteSpace(volumeName))
                {
                    volumeNames.Add(volumeName);
                }
            }
        }

        foreach (var volume in volumeNames)
        {
            if (dryRun)
            {
                await _stdout.WriteLineAsync($"Would remove volume {volume}").ConfigureAwait(false);
                continue;
            }

            await DockerCaptureAsync(["volume", "rm", volume], cancellationToken).ConfigureAwait(false);
        }

        await _stdout.WriteLineAsync("Uninstall complete.").ConfigureAwait(false);
        return 0;
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
        var exportFirst = args.Contains("--export", StringComparer.Ordinal);

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

        if (stopAll && exportFirst)
        {
            await _stderr.WriteLineAsync("--export and --all are mutually exclusive").ConfigureAwait(false);
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
            if (exportFirst)
            {
                var exportExitCode = await RunExportAsync(["export", "--container", target], cancellationToken).ConfigureAwait(false);
                if (exportExitCode != 0)
                {
                    failures++;
                    await _stderr.WriteLineAsync($"Failed to export data volume for container: {target}").ConfigureAwait(false);
                    if (!force)
                    {
                        continue;
                    }
                }
            }

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

        var pruneCandidates = new List<string>();
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

            pruneCandidates.Add(containerId);
        }

        if (!dryRun && !force && pruneCandidates.Count > 0)
        {
            if (Console.IsInputRedirected)
            {
                await _stderr.WriteLineAsync("gc requires --force in non-interactive mode.").ConfigureAwait(false);
                return 1;
            }

            await _stdout.WriteLineAsync($"About to remove {pruneCandidates.Count} containers. Continue? [y/N]").ConfigureAwait(false);
            var response = (Console.ReadLine() ?? string.Empty).Trim();
            if (!response.Equals("y", StringComparison.OrdinalIgnoreCase) &&
                !response.Equals("yes", StringComparison.OrdinalIgnoreCase))
            {
                await _stdout.WriteLineAsync("Aborted.").ConfigureAwait(false);
                return 1;
            }
        }

        foreach (var containerId in pruneCandidates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (dryRun)
            {
                await _stdout.WriteLineAsync($"Would remove container {containerId}").ConfigureAwait(false);
                continue;
            }

            var removeResult = await DockerRunAsync(["rm", "-f", containerId], cancellationToken).ConfigureAwait(false);
            if (removeResult != 0)
            {
                failures++;
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

    private static string ResolveHomeDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("HOME");
        }

        return string.IsNullOrWhiteSpace(home) ? Directory.GetCurrentDirectory() : home;
    }

    private static string ExpandHomePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return path;
        }

        if (!path.StartsWith("~", StringComparison.Ordinal))
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

    private async Task<string> ResolveChannelAsync(CancellationToken cancellationToken)
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

        var result = await RunParseTomlAsync(
            ["--file", configPath, "--key", "image.channel"],
            cancellationToken).ConfigureAwait(false);

        if (result.ExitCode != 0)
        {
            return "stable";
        }

        return string.Equals(result.StandardOutput.Trim(), "nightly", StringComparison.OrdinalIgnoreCase)
            ? "nightly"
            : "stable";
    }

    private async Task<string?> ResolveDataVolumeAsync(string workspace, string? explicitVolume, CancellationToken cancellationToken)
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

        var configPath = ResolveUserConfigPath();
        if (!File.Exists(configPath))
        {
            return "containai-data";
        }

        var normalizedWorkspace = Path.GetFullPath(ExpandHomePath(workspace));
        var workspaceState = await RunParseTomlAsync(
            ["--file", configPath, "--get-workspace", normalizedWorkspace],
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

        var globalResult = await RunParseTomlAsync(
            ["--file", configPath, "--key", "agent.data_volume"],
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

    private async Task<string?> ResolveDataVolumeFromContainerAsync(string containerName, string? explicitVolume, CancellationToken cancellationToken)
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

    private static bool ValidateOptions(IReadOnlyList<string> args, int startIndex, params string[] allowed)
    {
        var allowedSet = new HashSet<string>(allowed, StringComparer.Ordinal);
        for (var index = startIndex; index < args.Count; index++)
        {
            var token = args[index];
            if (!token.StartsWith("-", StringComparison.Ordinal))
            {
                continue;
            }

            if (allowedSet.Contains(token))
            {
                continue;
            }

            return false;
        }

        return true;
    }

    private static string GetRootHelpText()
    {
        return """
ContainAI - Run AI coding agents in a secure Docker sandbox

Usage: cai [subcommand] [options]

Subcommands:
  run           Start/attach to sandbox container (default if omitted)
  shell         Open interactive shell in running container
  exec          Run a command in container via SSH
  doctor        Check system capabilities and show diagnostics
  setup         Configure secure container isolation
  validate      Validate Secure Engine configuration
  docker        Run docker with ContainAI context
  import        Sync host configs to data volume
  export        Export data volume to .tgz archive
  sync          In-container config sync
  stop          Stop ContainAI containers
  status        Show container status and resource usage
  gc            Garbage collect stale containers/images
  ssh           Manage SSH configuration
  links         Verify and repair container symlinks
  config        Manage settings
  template      Manage templates
  update        Update ContainAI installation
  refresh       Pull latest base image and optionally rebuild template
  uninstall     Remove ContainAI system components
  completion    Generate shell completion scripts
  version       Show version
  help          Show this help message
  acp           ACP proxy tooling

Examples:
  cai
  cai shell
  cai exec ls -la
  cai stop --all
  cai doctor
""";
    }

    private static (string Version, string InstallType, string InstallDir) ResolveVersionInfo()
    {
        var installDir = ResolveInstallDirectory();
        var version = ResolveVersion(installDir);
        var installType = ResolveInstallType(installDir);
        return (version, installType, installDir);
    }

    private static string ResolveInstallDirectory()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in new[] { AppContext.BaseDirectory, Directory.GetCurrentDirectory() })
        {
            var current = Path.GetFullPath(root);
            while (!string.IsNullOrWhiteSpace(current))
            {
                if (seen.Add(current) && File.Exists(Path.Combine(current, "VERSION")))
                {
                    return current;
                }

                var parent = Directory.GetParent(current);
                if (parent is null)
                {
                    break;
                }

                current = parent.FullName;
            }
        }

        return Directory.GetCurrentDirectory();
    }

    private static string ResolveVersion(string installDir)
    {
        var versionFile = Path.Combine(installDir, "VERSION");
        if (File.Exists(versionFile))
        {
            var value = File.ReadAllText(versionFile).Trim();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        var assemblyVersion = Assembly.GetEntryAssembly()?.GetName().Version?.ToString()
            ?? Assembly.GetExecutingAssembly().GetName().Version?.ToString();

        return string.IsNullOrWhiteSpace(assemblyVersion) ? "0.0.0" : assemblyVersion;
    }

    private static string ResolveInstallType(string installDir)
    {
        if (Directory.Exists(Path.Combine(installDir, ".git")))
        {
            return "git";
        }

        var normalized = installDir.Replace('\\', '/');
        if (normalized.Contains("/.local/share/containai", StringComparison.Ordinal))
        {
            return "local";
        }

        return "installed";
    }

    private static string EscapeJson(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }

        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\t", "\\t", StringComparison.Ordinal);
    }

    private async Task<bool> CommandSucceedsAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private async Task<string?> ResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var configPath = ResolveUserConfigPath();
        if (File.Exists(configPath))
        {
            var workspaceResult = await RunParseTomlAsync(
                ["--file", configPath, "--get-workspace", workspace],
                cancellationToken).ConfigureAwait(false);

            if (workspaceResult.ExitCode == 0 && !string.IsNullOrWhiteSpace(workspaceResult.StandardOutput))
            {
                using var json = JsonDocument.Parse(workspaceResult.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("container_name", out var containerNameElement))
                {
                    var configuredName = containerNameElement.GetString();
                    if (!string.IsNullOrWhiteSpace(configuredName))
                    {
                        var inspect = await DockerCaptureAsync(
                            ["inspect", "--type", "container", configuredName],
                            cancellationToken).ConfigureAwait(false);
                        if (inspect.ExitCode == 0)
                        {
                            return configuredName;
                        }
                    }
                }
            }
        }

        var byLabel = await DockerCaptureAsync(
            ["ps", "-aq", "--filter", $"label=containai.workspace={workspace}"],
            cancellationToken).ConfigureAwait(false);

        if (byLabel.ExitCode != 0)
        {
            return null;
        }

        var ids = byLabel.StandardOutput
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (ids.Length == 0)
        {
            return null;
        }

        if (ids.Length > 1)
        {
            await _stderr.WriteLineAsync($"Multiple containers found for workspace: {workspace}").ConfigureAwait(false);
            return null;
        }

        var nameResult = await DockerCaptureAsync(
            ["inspect", "--format", "{{.Name}}", ids[0]],
            cancellationToken).ConfigureAwait(false);

        if (nameResult.ExitCode != 0)
        {
            return null;
        }

        return nameResult.StandardOutput.Trim().TrimStart('/');
    }

    private async Task CopyDirectoryAsync(string sourceDirectory, string destinationDirectory, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(destinationDirectory);

        foreach (var sourceFile in Directory.EnumerateFiles(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationFile = Path.Combine(destinationDirectory, Path.GetFileName(sourceFile));
            await using var sourceStream = File.OpenRead(sourceFile);
            await using var destinationStream = File.Create(destinationFile);
            await sourceStream.CopyToAsync(destinationStream, cancellationToken).ConfigureAwait(false);
        }

        foreach (var sourceSubdirectory in Directory.EnumerateDirectories(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationSubdirectory = Path.Combine(destinationDirectory, Path.GetFileName(sourceSubdirectory));
            await CopyDirectoryAsync(sourceSubdirectory, destinationSubdirectory, cancellationToken).ConfigureAwait(false);
        }
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
            catch (Exception killEx)
            {
                Console.Error.WriteLine($"Failed to terminate process '{fileName}' during cancellation: {killEx.Message}");
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
