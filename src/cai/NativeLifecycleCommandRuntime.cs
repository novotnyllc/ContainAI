using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class NativeLifecycleCommandRuntime
{
    private static readonly string[] ContainAiImagePrefixes =
    [
        "containai:",
        "ghcr.io/containai/",
        "ghcr.io/novotnyllc/containai",
    ];

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly NativeSessionCommandRuntime sessionRuntime;
    private readonly ContainerRuntimeCommandService containerRuntimeCommandService;

    public NativeLifecycleCommandRuntime(TextWriter? standardOutput = null, TextWriter? standardError = null)
    {
        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;
        sessionRuntime = new NativeSessionCommandRuntime(stdout, stderr);
        containerRuntimeCommandService = new ContainerRuntimeCommandService(stdout, stderr);
    }

    public Task<int> RunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count == 0)
        {
            return Task.FromResult(1);
        }

        return args[0] switch
        {
            "run" => sessionRuntime.RunRunAsync(args, cancellationToken),
            "shell" => sessionRuntime.RunShellAsync(args, cancellationToken),
            "exec" => sessionRuntime.RunExecAsync(args, cancellationToken),
            "docker" => RunDockerAsync(args, cancellationToken),
            "status" => RunStatusAsync(args, cancellationToken),
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
            "config" => RunConfigAsync(args, cancellationToken),
            "manifest" => RunManifestAsync(args, cancellationToken),
            "template" => RunTemplateAsync(args, cancellationToken),
            "ssh" => RunSshAsync(args, cancellationToken),
            "stop" => RunStopAsync(args, cancellationToken),
            "gc" => RunGcAsync(args, cancellationToken),
            "system" => containerRuntimeCommandService.RunAsync(args, cancellationToken),
            _ => Task.FromResult(1),
        };
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return sessionRuntime.RunRunAsync(options, cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return sessionRuntime.RunShellAsync(options, cancellationToken);
    }

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return sessionRuntime.RunExecAsync(options, cancellationToken);
    }

    public static Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunDockerCoreAsync(options.DockerArgs, cancellationToken);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunStatusCoreAsync(options.Json, options.Verbose, options.Workspace, options.Container, cancellationToken);
    }

    private async Task<int> RunDockerAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count > 1 && (args[1] is "-h" or "--help"))
        {
            await stdout.WriteLineAsync("Usage: cai docker [docker-args...]").ConfigureAwait(false);
            return 0;
        }

        return await RunDockerCoreAsync(args.Skip(1).ToArray(), cancellationToken).ConfigureAwait(false);
    }

    private static async Task<int> RunDockerCoreAsync(IReadOnlyList<string> dockerArguments, CancellationToken cancellationToken)
    {
        var executable = IsExecutableOnPath("containai-docker")
            ? "containai-docker"
            : "docker";

        var dockerArgs = new List<string>();
        if (string.Equals(executable, "docker", StringComparison.Ordinal))
        {
            var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(context))
            {
                dockerArgs.Add("--context");
                dockerArgs.Add(context!);
            }
        }

        foreach (var argument in dockerArguments)
        {
            dockerArgs.Add(argument);
        }

        return await RunProcessInteractiveAsync(executable, dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunStatusAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var outputJson = false;
        var verbose = false;
        string? workspace = null;
        string? container = null;

        for (var index = 1; index < args.Count; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--help":
                case "-h":
                    await stdout.WriteLineAsync("Usage: cai status [--workspace <path> | --container <name>] [--json] [--verbose]").ConfigureAwait(false);
                    return 0;
                case "--json":
                    outputJson = true;
                    break;
                case "--verbose":
                    verbose = true;
                    break;
                case "--workspace":
                    if (index + 1 >= args.Count || args[index + 1].StartsWith('-'))
                    {
                        await stderr.WriteLineAsync("--workspace requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    workspace = args[++index];
                    break;
                case "--container":
                    if (index + 1 >= args.Count || args[index + 1].StartsWith('-'))
                    {
                        await stderr.WriteLineAsync("--container requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    container = args[++index];
                    break;
                default:
                    if (token.StartsWith("--workspace=", StringComparison.Ordinal))
                    {
                        workspace = token[12..];
                    }
                    else if (token.StartsWith("--container=", StringComparison.Ordinal))
                    {
                        container = token[12..];
                    }
                    else
                    {
                        await stderr.WriteLineAsync($"Unknown status option: {token}").ConfigureAwait(false);
                        return 1;
                    }

                    break;
            }
        }

        return await RunStatusCoreAsync(outputJson, verbose, workspace, container, cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunStatusCoreAsync(
        bool outputJson,
        bool verbose,
        string? workspace,
        string? container,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(workspace) && !string.IsNullOrWhiteSpace(container))
        {
            await stderr.WriteLineAsync("--workspace and --container are mutually exclusive").ConfigureAwait(false);
            return 1;
        }

        var effectiveWorkspace = Path.GetFullPath(ExpandHomePath(workspace ?? Directory.GetCurrentDirectory()));
        if (string.IsNullOrWhiteSpace(container))
        {
            container = await ResolveWorkspaceContainerNameAsync(effectiveWorkspace, cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(container))
            {
                await stderr.WriteLineAsync($"No container found for workspace: {effectiveWorkspace}").ConfigureAwait(false);
                return 1;
            }
        }

        var discoveredContexts = await FindContainerContextsAsync(container, cancellationToken).ConfigureAwait(false);
        if (discoveredContexts.Count == 0)
        {
            await stderr.WriteLineAsync($"Container not found: {container}").ConfigureAwait(false);
            return 1;
        }

        if (discoveredContexts.Count > 1)
        {
            await stderr.WriteLineAsync($"Container '{container}' exists in multiple contexts: {string.Join(", ", discoveredContexts)}").ConfigureAwait(false);
            return 1;
        }

        var context = discoveredContexts[0];

        var managedResult = await DockerCaptureForContextAsync(
            context,
            ["inspect", "--format", "{{index .Config.Labels \"containai.managed\"}}", "--", container],
            cancellationToken).ConfigureAwait(false);
        if (managedResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync($"Failed to inspect container: {container}").ConfigureAwait(false);
            return 1;
        }

        if (!string.Equals(managedResult.StandardOutput.Trim(), "true", StringComparison.Ordinal))
        {
            await stderr.WriteLineAsync($"Container {container} exists but is not managed by ContainAI").ConfigureAwait(false);
            return 1;
        }

        var inspect = await DockerCaptureForContextAsync(
            context,
            ["inspect", "--format", "{{.State.Status}}|{{.Config.Image}}|{{.State.StartedAt}}", "--", container],
            cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            await stderr.WriteLineAsync($"Failed to inspect container: {container}").ConfigureAwait(false);
            return 1;
        }

        var parts = inspect.StandardOutput.Trim().Split('|');
        if (parts.Length < 3)
        {
            await stderr.WriteLineAsync("Unable to parse container status").ConfigureAwait(false);
            return 1;
        }

        var status = parts[0];
        var image = parts[1];
        var startedAt = parts[2];

        string? uptime = null;
        if (string.Equals(status, "running", StringComparison.Ordinal) &&
            DateTimeOffset.TryParse(startedAt, out var started))
        {
            var elapsed = DateTimeOffset.UtcNow - started;
            if (elapsed.TotalDays >= 1)
            {
                uptime = $"{(int)elapsed.TotalDays}d {elapsed.Hours}h {elapsed.Minutes}m";
            }
            else if (elapsed.TotalHours >= 1)
            {
                uptime = $"{elapsed.Hours}h {elapsed.Minutes}m";
            }
            else
            {
                uptime = $"{Math.Max(0, elapsed.Minutes)}m";
            }
        }

        string? memUsage = null;
        string? memLimit = null;
        string? cpuPercent = null;
        if (string.Equals(status, "running", StringComparison.Ordinal))
        {
            var stats = await DockerCaptureForContextAsync(
                context,
                ["stats", "--no-stream", "--format", "{{.MemUsage}}|{{.CPUPerc}}", "--", container],
                cancellationToken).ConfigureAwait(false);
            if (stats.ExitCode == 0)
            {
                var statsParts = stats.StandardOutput.Trim().Split('|');
                if (statsParts.Length >= 2)
                {
                    cpuPercent = statsParts[1];
                    var memParts = statsParts[0].Split(" / ", StringSplitOptions.TrimEntries);
                    if (memParts.Length == 2)
                    {
                        memUsage = memParts[0];
                        memLimit = memParts[1];
                    }
                }
            }
        }

        if (outputJson)
        {
            var jsonFields = new List<string>
            {
                $"\"container\":\"{EscapeJson(container)}\"",
                $"\"status\":\"{EscapeJson(status)}\"",
                $"\"image\":\"{EscapeJson(image)}\"",
                $"\"context\":\"{EscapeJson(context)}\"",
            };

            if (!string.IsNullOrWhiteSpace(uptime))
            {
                jsonFields.Add($"\"uptime\":\"{EscapeJson(uptime)}\"");
            }

            if (!string.IsNullOrWhiteSpace(memUsage))
            {
                jsonFields.Add($"\"memory_usage\":\"{EscapeJson(memUsage)}\"");
            }

            if (!string.IsNullOrWhiteSpace(memLimit))
            {
                jsonFields.Add($"\"memory_limit\":\"{EscapeJson(memLimit)}\"");
            }

            if (!string.IsNullOrWhiteSpace(cpuPercent))
            {
                jsonFields.Add($"\"cpu_percent\":\"{EscapeJson(cpuPercent)}\"");
            }

            await stdout.WriteLineAsync("{" + string.Join(",", jsonFields) + "}").ConfigureAwait(false);
            return 0;
        }

        await stdout.WriteLineAsync($"Container: {container}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Status: {status}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Image: {image}").ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(uptime))
        {
            await stdout.WriteLineAsync($"  Uptime: {uptime}").ConfigureAwait(false);
        }

        if (verbose)
        {
            await stdout.WriteLineAsync($"  Context: {context}").ConfigureAwait(false);
        }

        if (!string.IsNullOrWhiteSpace(memUsage) && !string.IsNullOrWhiteSpace(memLimit))
        {
            await stdout.WriteLineAsync($"  Memory: {memUsage} / {memLimit}").ConfigureAwait(false);
        }

        if (!string.IsNullOrWhiteSpace(cpuPercent))
        {
            await stdout.WriteLineAsync($"  CPU: {cpuPercent}").ConfigureAwait(false);
        }

        return 0;
    }

    private async Task<int> RunHelpAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (args.Count <= 1)
        {
            await stdout.WriteLineAsync(GetRootHelpText()).ConfigureAwait(false);
            return 0;
        }

        var topic = args[1];
        return topic switch
        {
            "config" => await WriteUsageAsync("Usage: cai config <list|get|set|unset|resolve-volume> [options]").ConfigureAwait(false),
            "template" => await WriteUsageAsync("Usage: cai template upgrade [name] [--dry-run]").ConfigureAwait(false),
            "ssh" => await WriteUsageAsync("Usage: cai ssh cleanup [--dry-run]").ConfigureAwait(false),
            "completion" => await WriteUsageAsync("Usage: cai completion suggest --line \"<command line>\" [--position <cursor>]").ConfigureAwait(false),
            "links" => await WriteUsageAsync("Usage: cai links <check|fix> [--name <container>] [--workspace <path>] [--dry-run]").ConfigureAwait(false),
            _ => await WriteUsageAsync(GetRootHelpText()).ConfigureAwait(false),
        };
    }

    private async Task<int> WriteUsageAsync(string usage)
    {
        await stdout.WriteLineAsync(usage).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunVersionAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var json = args.Contains("--json", StringComparer.Ordinal);
        var versionInfo = InstallMetadata.ResolveVersionInfo();
        var installType = InstallMetadata.GetInstallTypeLabel(versionInfo.InstallType);

        if (json)
        {
            await stdout.WriteLineAsync($"{{\"version\":\"{versionInfo.Version}\",\"install_type\":\"{installType}\",\"install_dir\":\"{EscapeJson(versionInfo.InstallDir)}\"}}").ConfigureAwait(false);
            return 0;
        }

        await stdout.WriteLineAsync(versionInfo.Version).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunDoctorAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count > 1 && string.Equals(args[1], "fix", StringComparison.Ordinal))
        {
            return await RunDoctorFixAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false);
        }

        if (!ValidateOptions(args, 1, "--json", "--build-templates", "--reset-lima", "--help", "-h"))
        {
            await stderr.WriteLineAsync("Unknown doctor option. Use 'cai doctor --help'.").ConfigureAwait(false);
            return 1;
        }

        if (args.Contains("--help", StringComparer.Ordinal) || args.Contains("-h", StringComparer.Ordinal))
        {
            await stdout.WriteLineAsync("Usage: cai doctor [--json] [--build-templates] [--reset-lima]").ConfigureAwait(false);
            await stdout.WriteLineAsync("       cai doctor fix [--all | container [--all|<name>] | template [--all|<name>] ]").ConfigureAwait(false);
            return 0;
        }

        var outputJson = args.Contains("--json", StringComparer.Ordinal);
        var buildTemplates = args.Contains("--build-templates", StringComparer.Ordinal);
        var resetLima = args.Contains("--reset-lima", StringComparer.Ordinal);

        if (resetLima)
        {
            if (!OperatingSystem.IsMacOS())
            {
                await stderr.WriteLineAsync("--reset-lima is only available on macOS").ConfigureAwait(false);
                return 1;
            }

            await stdout.WriteLineAsync("Resetting Lima VM containai...").ConfigureAwait(false);
            await RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
            await RunProcessCaptureAsync("docker", ["context", "rm", "-f", "containai-docker"], cancellationToken).ConfigureAwait(false);
        }

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
        var templateStatus = true;
        if (buildTemplates)
        {
            templateStatus = await ValidateTemplatesAsync(cancellationToken).ConfigureAwait(false);
        }

        if (outputJson)
        {
            await stdout.WriteLineAsync($"{{\"docker_cli\":{dockerCli.ToString().ToLowerInvariant()},\"context\":{contextExists.ToString().ToLowerInvariant()},\"docker_daemon\":{dockerInfo.ToString().ToLowerInvariant()},\"sysbox_runtime\":{sysboxRuntime.ToString().ToLowerInvariant()},\"templates\":{templateStatus.ToString().ToLowerInvariant()}}}").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync($"Docker CLI: {(dockerCli ? "ok" : "missing")}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Context: {(contextExists ? contextName : "missing")}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Docker daemon: {(dockerInfo ? "ok" : "unreachable")}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"sysbox-runc runtime: {(sysboxRuntime ? "ok" : "missing")}").ConfigureAwait(false);
            if (buildTemplates)
            {
                await stdout.WriteLineAsync($"Templates: {(templateStatus ? "ok" : "failed")}").ConfigureAwait(false);
            }
        }

        return dockerCli && contextExists && dockerInfo && sysboxRuntime && templateStatus ? 0 : 1;
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
        var skipTemplates = args.Contains("--skip-templates", StringComparer.Ordinal);
        var showHelp = args.Contains("--help", StringComparer.Ordinal) || args.Contains("-h", StringComparer.Ordinal);
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai setup [--dry-run] [--verbose] [--skip-templates]").ConfigureAwait(false);
            return 0;
        }

        if (!ValidateOptions(args, 1, "--dry-run", "--verbose", "--skip-templates", "--help", "-h"))
        {
            await stderr.WriteLineAsync("Unknown setup option. Use 'cai setup --help'.").ConfigureAwait(false);
            return 1;
        }

        var home = ResolveHomeDirectory();
        var containAiDir = Path.Combine(home, ".config", "containai");
        var sshDir = Path.Combine(home, ".ssh", "containai.d");
        var sshKeyPath = Path.Combine(containAiDir, "id_containai");
        var socketPath = "/var/run/containai-docker.sock";

        if (dryRun)
        {
            await stdout.WriteLineAsync($"Would create {containAiDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would create {sshDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would generate SSH key {sshKeyPath}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would verify runtime socket {socketPath}").ConfigureAwait(false);
            await stdout.WriteLineAsync("Would create Docker context containai-docker").ConfigureAwait(false);
            if (!skipTemplates)
            {
                await stdout.WriteLineAsync($"Would install templates to {ResolveTemplatesDirectory()}").ConfigureAwait(false);
            }

            return 0;
        }

        if (!await CommandSucceedsAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false))
        {
            await stderr.WriteLineAsync("Docker CLI is required for setup.").ConfigureAwait(false);
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
                await stderr.WriteLineAsync(keygen.StandardError.Trim()).ConfigureAwait(false);
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
                    await stderr.WriteLineAsync(error).ConfigureAwait(false);
                }
            }
        }
        else
        {
            await stderr.WriteLineAsync($"Setup warning: runtime socket not found at {socketPath}.").ConfigureAwait(false);
        }

        if (!skipTemplates)
        {
            var templateResult = await RestoreTemplatesAsync(templateName: null, includeAll: true, cancellationToken).ConfigureAwait(false);
            if (templateResult != 0 && verbose)
            {
                await stderr.WriteLineAsync("Template installation completed with warnings.").ConfigureAwait(false);
            }
        }

        var doctorExitCode = await RunDoctorAsync(["doctor"], cancellationToken).ConfigureAwait(false);
        if (doctorExitCode != 0)
        {
            await stderr.WriteLineAsync("Setup completed with warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Setup complete.").ConfigureAwait(false);
        return doctorExitCode;
    }

    private async Task<int> RunDoctorFixAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
        var fixAll = args.Contains("--all", StringComparer.Ordinal);

        var target = args.FirstOrDefault(static token => !token.StartsWith('-'));
        var targetArg = args.SkipWhile(static token => token.StartsWith('-'))
            .Skip(1)
            .FirstOrDefault(static token => !token.StartsWith('-'));

        if (target is null && !fixAll)
        {
            await stdout.WriteLineAsync("Available doctor fix targets:").ConfigureAwait(false);
            await stdout.WriteLineAsync("  --all").ConfigureAwait(false);
            await stdout.WriteLineAsync("  container [--all|<name>]").ConfigureAwait(false);
            await stdout.WriteLineAsync("  template [--all|<name>]").ConfigureAwait(false);
            return 0;
        }

        var containAiDir = Path.Combine(ResolveHomeDirectory(), ".config", "containai");
        var sshDir = Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");
        if (dryRun)
        {
            await stdout.WriteLineAsync($"Would create {containAiDir} and {sshDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync("Would ensure SSH include directive and cleanup stale SSH configs").ConfigureAwait(false);
        }
        else
        {
            Directory.CreateDirectory(containAiDir);
            Directory.CreateDirectory(sshDir);
            await EnsureSshIncludeDirectiveAsync(cancellationToken).ConfigureAwait(false);
            await RunSshAsync(["ssh", "cleanup"], cancellationToken).ConfigureAwait(false);
        }

        if (fixAll || string.Equals(target, "template", StringComparison.Ordinal))
        {
            var templateResult = await RestoreTemplatesAsync(targetArg, includeAll: fixAll || string.Equals(targetArg, "--all", StringComparison.Ordinal), cancellationToken).ConfigureAwait(false);
            if (templateResult != 0)
            {
                return templateResult;
            }
        }

        if (fixAll || string.Equals(target, "container", StringComparison.Ordinal))
        {
            if (string.IsNullOrWhiteSpace(targetArg) || string.Equals(targetArg, "--all", StringComparison.Ordinal))
            {
                await stdout.WriteLineAsync("Container fix completed (SSH cleanup applied).").ConfigureAwait(false);
            }
            else
            {
                var exists = await DockerContainerExistsAsync(targetArg, cancellationToken).ConfigureAwait(false);
                if (!exists)
                {
                    await stderr.WriteLineAsync($"Container not found: {targetArg}").ConfigureAwait(false);
                    return 1;
                }

                await stdout.WriteLineAsync($"Container fix completed for {targetArg}.").ConfigureAwait(false);
            }
        }

        return 0;
    }

    private static async Task EnsureSshIncludeDirectiveAsync(CancellationToken cancellationToken)
    {
        var userSshConfig = Path.Combine(ResolveHomeDirectory(), ".ssh", "config");
        var includeLine = $"Include {Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d")}/*.conf";

        Directory.CreateDirectory(Path.GetDirectoryName(userSshConfig)!);
        if (!File.Exists(userSshConfig))
        {
            await File.WriteAllTextAsync(userSshConfig, includeLine + Environment.NewLine, cancellationToken).ConfigureAwait(false);
            return;
        }

        var content = await File.ReadAllTextAsync(userSshConfig, cancellationToken).ConfigureAwait(false);
        if (content.Contains(includeLine, StringComparison.Ordinal))
        {
            return;
        }

        var normalized = content.TrimEnd();
        var merged = string.IsNullOrWhiteSpace(normalized)
            ? includeLine + Environment.NewLine
            : normalized + Environment.NewLine + includeLine + Environment.NewLine;
        await File.WriteAllTextAsync(userSshConfig, merged, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<bool> ValidateTemplatesAsync(CancellationToken cancellationToken)
    {
        var templatesRoot = ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            return false;
        }

        foreach (var dockerfile in Directory.EnumerateFiles(templatesRoot, "Dockerfile", SearchOption.AllDirectories))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var directory = Path.GetDirectoryName(dockerfile)!;
            var imageName = $"containai-template-check-{Path.GetFileName(directory)}";
            var build = await DockerCaptureAsync(["build", "-q", "-f", dockerfile, "-t", imageName, directory], cancellationToken).ConfigureAwait(false);
            if (build.ExitCode != 0)
            {
                return false;
            }
        }

        return true;
    }

    private async Task<int> RestoreTemplatesAsync(string? templateName, bool includeAll, CancellationToken cancellationToken)
    {
        var sourceRoot = ResolveBundledTemplatesDirectory();
        if (string.IsNullOrWhiteSpace(sourceRoot) || !Directory.Exists(sourceRoot))
        {
            await stderr.WriteLineAsync("Bundled templates not found; skipping template restore.").ConfigureAwait(false);
            return 0;
        }

        var destinationRoot = ResolveTemplatesDirectory();
        Directory.CreateDirectory(destinationRoot);

        var sourceTemplates = Directory.EnumerateDirectories(sourceRoot).ToArray();
        if (!string.IsNullOrWhiteSpace(templateName) && !includeAll)
        {
            sourceTemplates = sourceTemplates
                .Where(path => string.Equals(Path.GetFileName(path), templateName, StringComparison.Ordinal))
                .ToArray();
        }

        foreach (var source in sourceTemplates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var template = Path.GetFileName(source);
            var destination = Path.Combine(destinationRoot, template);
            if (Directory.Exists(destination))
            {
                Directory.Delete(destination, recursive: true);
            }

            await CopyDirectoryAsync(source, destination, cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync($"Restored template '{template}'").ConfigureAwait(false);
        }

        return 0;
    }

    private static string ResolveBundledTemplatesDirectory()
    {
        var installRoot = InstallMetadata.ResolveInstallDirectory();
        foreach (var candidate in new[]
                 {
                     Path.Combine(installRoot, "templates"),
                     Path.Combine(installRoot, "src", "templates"),
                 })
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        return string.Empty;
    }

    private async Task<int> RunImportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var options = ParseImportOptions(args);
        if (options.Error is not null)
        {
            await stderr.WriteLineAsync(options.Error).ConfigureAwait(false);
            return 1;
        }

        var workspace = string.IsNullOrWhiteSpace(options.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(ExpandHomePath(options.Workspace));
        var explicitConfigPath = string.IsNullOrWhiteSpace(options.ConfigPath)
            ? null
            : Path.GetFullPath(ExpandHomePath(options.ConfigPath));

        if (!string.IsNullOrWhiteSpace(explicitConfigPath) && !File.Exists(explicitConfigPath))
        {
            await stderr.WriteLineAsync($"Config file not found: {explicitConfigPath}").ConfigureAwait(false);
            return 1;
        }

        var volume = await ResolveDataVolumeAsync(workspace, options.ExplicitVolume, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            await stderr.WriteLineAsync("Unable to resolve data volume. Use --data-volume.").ConfigureAwait(false);
            return 1;
        }

        var sourcePath = string.IsNullOrWhiteSpace(options.SourcePath)
            ? ResolveHomeDirectory()
            : Path.GetFullPath(ExpandHomePath(options.SourcePath));
        if (!File.Exists(sourcePath) && !Directory.Exists(sourcePath))
        {
            await stderr.WriteLineAsync($"Import source not found: {sourcePath}").ConfigureAwait(false);
            return 1;
        }

        var excludePriv = await ResolveImportExcludePrivAsync(workspace, explicitConfigPath, cancellationToken).ConfigureAwait(false);
        var context = ResolveDockerContextName();

        await stdout.WriteLineAsync($"Using data volume: {volume}").ConfigureAwait(false);
        if (options.DryRun)
        {
            await stdout.WriteLineAsync($"Dry-run context: {context}").ConfigureAwait(false);
        }

        if (!options.DryRun)
        {
            var ensureVolume = await DockerCaptureAsync(["volume", "create", volume], cancellationToken).ConfigureAwait(false);
            if (ensureVolume.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureVolume.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        ManifestEntry[] manifestEntries;
        try
        {
            var manifestDirectory = ResolveImportManifestDirectory();
            manifestEntries = ManifestTomlParser.Parse(manifestDirectory, includeDisabled: false, includeSourceFile: false)
                .Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal))
                .Where(static entry => !string.IsNullOrWhiteSpace(entry.Source))
                .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
                .ToArray();
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }

        if (File.Exists(sourcePath))
        {
            if (!sourcePath.EndsWith(".tgz", StringComparison.OrdinalIgnoreCase))
            {
                await stderr.WriteLineAsync($"Unsupported import source file type: {sourcePath}").ConfigureAwait(false);
                return 1;
            }

            if (!options.DryRun)
            {
                var restoreCode = await RestoreArchiveImportAsync(volume, sourcePath, excludePriv, cancellationToken).ConfigureAwait(false);
                if (restoreCode != 0)
                {
                    return restoreCode;
                }

                var applyOverrideCode = await ApplyImportOverridesAsync(
                    volume,
                    manifestEntries,
                    options.NoSecrets,
                    options.DryRun,
                    options.Verbose,
                    cancellationToken).ConfigureAwait(false);
                if (applyOverrideCode != 0)
                {
                    return applyOverrideCode;
                }
            }

            await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
            return 0;
        }

        var additionalImportPaths = await ResolveAdditionalImportPathsAsync(
            workspace,
            explicitConfigPath,
            excludePriv,
            sourcePath,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);

        if (!options.DryRun)
        {
            var initCode = await InitializeImportTargetsAsync(volume, sourcePath, manifestEntries, options.NoSecrets, cancellationToken).ConfigureAwait(false);
            if (initCode != 0)
            {
                return initCode;
            }
        }

        foreach (var entry in manifestEntries)
        {
            if (options.NoSecrets && entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                if (options.Verbose)
                {
                    await stderr.WriteLineAsync($"Skipping secret entry: {entry.Source}").ConfigureAwait(false);
                }

                continue;
            }

            var copyCode = await ImportManifestEntryAsync(
                volume,
                sourcePath,
                entry,
                excludePriv,
                options.NoExcludes,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        if (!options.DryRun)
        {
            var secretPermissionsCode = await EnforceSecretPathPermissionsAsync(
                volume,
                manifestEntries,
                options.NoSecrets,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (secretPermissionsCode != 0)
            {
                return secretPermissionsCode;
            }
        }

        foreach (var additionalPath in additionalImportPaths)
        {
            var copyCode = await ImportAdditionalPathAsync(
                volume,
                additionalPath,
                options.NoExcludes,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        var envCode = await ImportEnvironmentVariablesAsync(
            volume,
            workspace,
            explicitConfigPath,
            options.DryRun,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
        if (envCode != 0)
        {
            return envCode;
        }

        var overrideCode = await ApplyImportOverridesAsync(
            volume,
            manifestEntries,
            options.NoSecrets,
            options.DryRun,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
        if (overrideCode != 0)
        {
            return overrideCode;
        }

        await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var secretDirectories = new HashSet<string>(StringComparer.Ordinal);
        var secretFiles = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in manifestEntries)
        {
            if (!entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                continue;
            }

            if (noSecrets)
            {
                continue;
            }

            var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
            if (entry.Flags.Contains('d', StringComparison.Ordinal))
            {
                secretDirectories.Add(normalizedTarget);
            }
            else
            {
                secretFiles.Add(normalizedTarget);
                var parent = Path.GetDirectoryName(normalizedTarget)?.Replace("\\", "/", StringComparison.Ordinal);
                if (!string.IsNullOrWhiteSpace(parent))
                {
                    secretDirectories.Add(parent);
                }
            }
        }

        if (secretDirectories.Count == 0 && secretFiles.Count == 0)
        {
            return 0;
        }

        var commandBuilder = new StringBuilder();
        foreach (var directory in secretDirectories.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -d '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' ]; then chmod 700 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' || true; fi; ");
        }

        foreach (var file in secretFiles.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -f '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' ]; then chmod 600 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' || true; fi; ");
        }

        var result = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", commandBuilder.ToString()],
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(result.StandardError))
            {
                await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        if (verbose)
        {
            await stdout.WriteLineAsync("[INFO] Enforced secret path permissions").ConfigureAwait(false);
        }

        return 0;
    }

    private static ParsedImportOptions ParseImportOptions(IReadOnlyList<string> args)
    {
        string? sourcePath = null;
        string? explicitVolume = null;
        string? workspace = null;
        string? configPath = null;
        var dryRun = false;
        var noExcludes = false;
        var noSecrets = false;
        var verbose = false;

        for (var index = 1; index < args.Count; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--from":
                    if (index + 1 >= args.Count)
                    {
                        return ParsedImportOptions.WithError("--from requires a value");
                    }

                    sourcePath = args[++index];
                    break;
                case "--data-volume":
                    if (index + 1 >= args.Count)
                    {
                        return ParsedImportOptions.WithError("--data-volume requires a value");
                    }

                    explicitVolume = args[++index];
                    break;
                case "--workspace":
                    if (index + 1 >= args.Count)
                    {
                        return ParsedImportOptions.WithError("--workspace requires a value");
                    }

                    workspace = args[++index];
                    break;
                case "--config":
                    if (index + 1 >= args.Count)
                    {
                        return ParsedImportOptions.WithError("--config requires a value");
                    }

                    configPath = args[++index];
                    break;
                case "--dry-run":
                    dryRun = true;
                    break;
                case "--no-excludes":
                    noExcludes = true;
                    break;
                case "--no-secrets":
                    noSecrets = true;
                    break;
                case "--verbose":
                    verbose = true;
                    break;
                default:
                    if (token.StartsWith("--from=", StringComparison.Ordinal))
                    {
                        sourcePath = token[7..];
                    }
                    else if (token.StartsWith("--data-volume=", StringComparison.Ordinal))
                    {
                        explicitVolume = token[14..];
                    }
                    else if (token.StartsWith("--workspace=", StringComparison.Ordinal))
                    {
                        workspace = token[12..];
                    }
                    else if (token.StartsWith("--config=", StringComparison.Ordinal))
                    {
                        configPath = token[9..];
                    }
                    else if (token.StartsWith('-'))
                    {
                        return ParsedImportOptions.WithError($"Unknown import option: {token}");
                    }
                    else if (string.IsNullOrWhiteSpace(sourcePath))
                    {
                        sourcePath = token;
                    }

                    break;
            }
        }

        return new ParsedImportOptions(sourcePath, explicitVolume, workspace, configPath, dryRun, noExcludes, noSecrets, verbose, null);
    }

    private static async Task<bool> ResolveImportExcludePrivAsync(string workspace, string? explicitConfigPath, CancellationToken cancellationToken)
    {
        var configPath = !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : ResolveConfigPath(workspace);
        if (!File.Exists(configPath))
        {
            return true;
        }

        var result = await RunParseTomlAsync(["--file", configPath, "--key", "import.exclude_priv"], cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return true;
        }

        return !bool.TryParse(result.StandardOutput.Trim(), out var parsed) || parsed;
    }

    private async Task<IReadOnlyList<AdditionalImportPath>> ResolveAdditionalImportPathsAsync(
        string workspace,
        string? explicitConfigPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : ResolveConfigPath(workspace);
        if (!File.Exists(configPath))
        {
            return [];
        }

        var result = await RunParseTomlAsync(["--file", configPath, "--json"], cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (verbose && !string.IsNullOrWhiteSpace(result.StandardError))
            {
                await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(result.StandardOutput);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("import", out var importElement) ||
                importElement.ValueKind != JsonValueKind.Object ||
                !importElement.TryGetProperty("additional_paths", out var pathsElement))
            {
                return [];
            }

            if (pathsElement.ValueKind != JsonValueKind.Array)
            {
                await stderr.WriteLineAsync("[WARN] [import].additional_paths must be a list; ignoring").ConfigureAwait(false);
                return [];
            }

            var values = new List<AdditionalImportPath>();
            var seenSources = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in pathsElement.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.String)
                {
                    await stderr.WriteLineAsync($"[WARN] [import].additional_paths item must be a string; got {item.ValueKind}").ConfigureAwait(false);
                    continue;
                }

                var rawPath = item.GetString();
                if (!TryResolveAdditionalImportPath(rawPath, sourceRoot, excludePriv, out var resolved, out var warning))
                {
                    if (!string.IsNullOrWhiteSpace(warning))
                    {
                        await stderr.WriteLineAsync(warning).ConfigureAwait(false);
                    }

                    continue;
                }

                if (!seenSources.Add(resolved.SourcePath))
                {
                    continue;
                }

                values.Add(resolved);
            }

            return values;
        }
        catch (JsonException ex)
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"[WARN] Failed to parse config JSON for additional paths: {ex.Message}").ConfigureAwait(false);
            }

            return [];
        }
    }

    private static bool TryResolveAdditionalImportPath(
        string? rawPath,
        string sourceRoot,
        bool excludePriv,
        out AdditionalImportPath resolved,
        out string? warning)
    {
        resolved = default;
        warning = null;

        if (string.IsNullOrWhiteSpace(rawPath))
        {
            warning = "[WARN] [import].additional_paths entry is empty; skipping";
            return false;
        }

        if (rawPath.Contains(':', StringComparison.Ordinal))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' contains ':'; skipping";
            return false;
        }

        var effectiveHome = Path.GetFullPath(sourceRoot);
        var expandedPath = rawPath;
        if (rawPath.StartsWith('~'))
        {
            expandedPath = rawPath.Length == 1
                ? effectiveHome
                : rawPath[1] switch
                {
                    '/' or '\\' => Path.Combine(effectiveHome, rawPath[2..]),
                    _ => rawPath,
                };
        }
        if (rawPath.StartsWith('~') && !rawPath.StartsWith("~/", StringComparison.Ordinal) && !rawPath.StartsWith("~\\", StringComparison.Ordinal))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' uses unsupported user-home expansion; use ~/...";
            return false;
        }

        if (!Path.IsPathRooted(expandedPath))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' must be ~/... or absolute under HOME";
            return false;
        }

        var fullPath = Path.GetFullPath(expandedPath);
        if (!IsPathWithinDirectory(fullPath, effectiveHome))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' escapes HOME; skipping";
            return false;
        }

        if (!File.Exists(fullPath) && !Directory.Exists(fullPath))
        {
            return false;
        }

        if (ContainsSymlinkComponent(effectiveHome, fullPath))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' contains symlink components; skipping";
            return false;
        }

        var targetRelativePath = MapAdditionalPathTarget(effectiveHome, fullPath);
        if (string.IsNullOrWhiteSpace(targetRelativePath))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' resolved to an empty target; skipping";
            return false;
        }

        var isDirectory = Directory.Exists(fullPath);
        var applyPrivFilter = excludePriv && IsBashrcDirectoryPath(effectiveHome, fullPath);
        resolved = new AdditionalImportPath(fullPath, targetRelativePath, isDirectory, applyPrivFilter);
        return true;
    }

    private static bool IsPathWithinDirectory(string path, string directory)
    {
        var normalizedDirectory = Path.GetFullPath(directory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var normalizedPath = Path.GetFullPath(path)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (string.Equals(normalizedPath, normalizedDirectory, StringComparison.Ordinal))
        {
            return true;
        }

        return normalizedPath.StartsWith(
            normalizedDirectory + Path.DirectorySeparatorChar,
            StringComparison.Ordinal);
    }

    private static bool ContainsSymlinkComponent(string baseDirectory, string fullPath)
    {
        var relative = Path.GetRelativePath(baseDirectory, fullPath);
        if (relative.StartsWith("..", StringComparison.Ordinal))
        {
            return true;
        }

        var current = Path.GetFullPath(baseDirectory);
        var segments = relative.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);
        foreach (var segment in segments)
        {
            current = Path.Combine(current, segment);
            if (!File.Exists(current) && !Directory.Exists(current))
            {
                continue;
            }

            if (IsSymbolicLinkPath(current))
            {
                return true;
            }
        }

        return false;
    }

    private static string MapAdditionalPathTarget(string homeDirectory, string fullPath)
    {
        var relative = Path.GetRelativePath(homeDirectory, fullPath).Replace('\\', '/');
        if (string.Equals(relative, ".", StringComparison.Ordinal))
        {
            return string.Empty;
        }

        var segments = relative.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0)
        {
            return string.Empty;
        }

        var first = segments[0];
        if (first.StartsWith('.'))
        {
            first = first.TrimStart('.');
        }

        if (string.IsNullOrWhiteSpace(first))
        {
            return string.Empty;
        }

        segments[0] = first;
        return string.Join('/', segments);
    }

    private static bool IsBashrcDirectoryPath(string homeDirectory, string fullPath)
    {
        var normalized = Path.GetFullPath(fullPath);
        var bashrcDir = Path.Combine(Path.GetFullPath(homeDirectory), ".bashrc.d");
        return IsPathWithinDirectory(normalized, bashrcDir);
    }

    private async Task<int> ImportAdditionalPathAsync(
        string volume,
        AdditionalImportPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            await stdout.WriteLineAsync($"[DRY-RUN] Would sync additional path {additionalPath.SourcePath} -> {additionalPath.TargetPath}").ConfigureAwait(false);
            return 0;
        }

        if (verbose && noExcludes)
        {
            await stdout.WriteLineAsync("[INFO] --no-excludes does not disable .priv. filtering for additional paths").ConfigureAwait(false);
        }

        var ensureCommand = additionalPath.IsDirectory
            ? $"mkdir -p '/target/{EscapeForSingleQuotedShell(additionalPath.TargetPath)}'"
            : $"mkdir -p \"$(dirname '/target/{EscapeForSingleQuotedShell(additionalPath.TargetPath)}')\"";
        var ensureResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", ensureCommand],
            cancellationToken).ConfigureAwait(false);
        if (ensureResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(ensureResult.StandardError))
            {
                await stderr.WriteLineAsync(ensureResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        var rsyncArgs = new List<string>
        {
            "run",
            "--rm",
            "--entrypoint",
            "rsync",
            "-v",
            $"{volume}:/target",
            "-v",
            $"{additionalPath.SourcePath}:/source:ro",
            ResolveRsyncImage(),
            "-a",
        };

        if (additionalPath.ApplyPrivFilter)
        {
            rsyncArgs.Add("--exclude=*.priv.*");
        }

        if (additionalPath.IsDirectory)
        {
            rsyncArgs.Add("/source/");
            rsyncArgs.Add($"/target/{additionalPath.TargetPath.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add("/source");
            rsyncArgs.Add($"/target/{additionalPath.TargetPath}");
        }

        var result = await DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            var normalizedError = errorOutput.Trim();
            if (normalizedError.Contains("could not make way for new symlink", StringComparison.OrdinalIgnoreCase) &&
                !normalizedError.Contains("cannot delete non-empty directory", StringComparison.OrdinalIgnoreCase))
            {
                normalizedError += $"{Environment.NewLine}cannot delete non-empty directory";
            }

            await stderr.WriteLineAsync(normalizedError).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private static string ResolveDockerContextName()
    {
        var explicitContext = Environment.GetEnvironmentVariable("DOCKER_CONTEXT");
        if (!string.IsNullOrWhiteSpace(explicitContext))
        {
            return explicitContext;
        }

        return "default";
    }

    private static string ResolveRsyncImage()
    {
        var configured = Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }

    private async Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken)
    {
        var clear = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", "find /mnt/agent-data -mindepth 1 -delete"],
            cancellationToken).ConfigureAwait(false);
        if (clear.ExitCode != 0)
        {
            await stderr.WriteLineAsync(clear.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        var archiveDirectory = Path.GetDirectoryName(archivePath)!;
        var archiveName = Path.GetFileName(archivePath);
        var extractArgs = new List<string>
        {
            "run",
            "--rm",
            "-v",
            $"{volume}:/mnt/agent-data",
            "-v",
            $"{archiveDirectory}:/backup:ro",
            "alpine:3.20",
            "tar",
        };
        if (excludePriv)
        {
            extractArgs.Add("--exclude=./shell/bashrc.d/*.priv.*");
            extractArgs.Add("--exclude=shell/bashrc.d/*.priv.*");
        }

        extractArgs.Add("-xzf");
        extractArgs.Add($"/backup/{archiveName}");
        extractArgs.Add("-C");
        extractArgs.Add("/mnt/agent-data");

        var extract = await DockerCaptureAsync(extractArgs, cancellationToken).ConfigureAwait(false);
        if (extract.ExitCode != 0)
        {
            await stderr.WriteLineAsync(extract.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        foreach (var entry in entries)
        {
            if (noSecrets && entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                continue;
            }

            var sourcePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
            var sourceExists = Directory.Exists(sourcePath) || File.Exists(sourcePath);
            var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
            var isFile = entry.Flags.Contains('f', StringComparison.Ordinal);
            if (entry.Optional && !sourceExists)
            {
                continue;
            }

            if (isDirectory)
            {
                var command = $"mkdir -p '/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}' && chown -R 1000:1000 '/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}' || true";
                if (entry.Flags.Contains('s', StringComparison.Ordinal))
                {
                    command += $" && chmod 700 '/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}'";
                }

                var ensureDir = await DockerCaptureAsync(
                    ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", command],
                    cancellationToken).ConfigureAwait(false);
                if (ensureDir.ExitCode != 0)
                {
                    await stderr.WriteLineAsync(ensureDir.StandardError.Trim()).ConfigureAwait(false);
                    return 1;
                }

                continue;
            }

            if (!isFile)
            {
                continue;
            }

            if (entry.Optional && !sourceExists)
            {
                continue;
            }

            var ensureFileCommand = new StringBuilder();
            ensureFileCommand.Append($"dest='/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}'; ");
            ensureFileCommand.Append("mkdir -p \"$(dirname \"$dest\")\"; ");
            ensureFileCommand.Append("if [ ! -f \"$dest\" ]; then : > \"$dest\"; fi; ");
            if (entry.Flags.Contains('j', StringComparison.Ordinal))
            {
                ensureFileCommand.Append("if [ ! -s \"$dest\" ]; then printf '{}' > \"$dest\"; fi; ");
            }

            ensureFileCommand.Append("chown 1000:1000 \"$dest\" || true; ");
            if (entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                ensureFileCommand.Append("chmod 600 \"$dest\"; ");
            }

            var ensureFile = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", ensureFileCommand.ToString()],
                cancellationToken).ConfigureAwait(false);
            if (ensureFile.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureFile.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        return 0;
    }

    private async Task<int> ImportManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var sourceAbsolutePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
        var sourceExists = Directory.Exists(sourceAbsolutePath) || File.Exists(sourceAbsolutePath);
        if (!sourceExists)
        {
            if (verbose && !entry.Optional)
            {
                await stderr.WriteLineAsync($"Source not found: {entry.Source}").ConfigureAwait(false);
            }

            return 0;
        }

        if (dryRun)
        {
            await stdout.WriteLineAsync($"[DRY-RUN] Would sync {entry.Source} -> {entry.Target}").ConfigureAwait(false);
            return 0;
        }

        var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal) && Directory.Exists(sourceAbsolutePath);
        var normalizedSource = entry.Source.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
        var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');

        var rsyncArgs = new List<string>
        {
            "run",
            "--rm",
            "--entrypoint",
            "rsync",
            "-v",
            $"{volume}:/target",
            "-v",
            $"{sourceRoot}:/source:ro",
            ResolveRsyncImage(),
            "-a",
        };

        if (entry.Flags.Contains('m', StringComparison.Ordinal))
        {
            rsyncArgs.Add("--delete");
        }

        if (entry.Flags.Contains('x', StringComparison.Ordinal))
        {
            rsyncArgs.Add("--exclude=.system/");
        }

        if (entry.Flags.Contains('p', StringComparison.Ordinal) && excludePriv)
        {
            rsyncArgs.Add("--exclude=*.priv.*");
        }

        if (isDirectory)
        {
            rsyncArgs.Add($"/source/{normalizedSource.TrimEnd('/')}/");
            rsyncArgs.Add($"/target/{normalizedTarget.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add($"/source/{normalizedSource}");
            rsyncArgs.Add($"/target/{normalizedTarget}");
        }

        var result = await DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
            return 1;
        }

        var postCopyCode = await ApplyManifestPostCopyRulesAsync(
            volume,
            entry,
            dryRun,
            verbose,
            cancellationToken).ConfigureAwait(false);
        if (postCopyCode != 0)
        {
            return postCopyCode;
        }

        if (isDirectory)
        {
            var symlinkCode = await RelinkImportedDirectorySymlinksAsync(
                volume,
                sourceAbsolutePath,
                normalizedTarget,
                cancellationToken).ConfigureAwait(false);
            if (symlinkCode != 0)
            {
                return symlinkCode;
            }
        }

        return 0;
    }

    private async Task<int> RelinkImportedDirectorySymlinksAsync(
        string volume,
        string sourceDirectoryPath,
        string targetRelativePath,
        CancellationToken cancellationToken)
    {
        var symlinks = CollectSymlinksForRelink(sourceDirectoryPath);
        if (symlinks.Count == 0)
        {
            return 0;
        }

        var operations = new List<(string LinkPath, string RelativeTarget)>();
        foreach (var symlink in symlinks)
        {
            if (!Path.IsPathRooted(symlink.Target))
            {
                continue;
            }

            var absoluteTarget = Path.GetFullPath(symlink.Target);
            if (!IsPathWithinDirectory(absoluteTarget, sourceDirectoryPath))
            {
                await stderr.WriteLineAsync($"[WARN] preserving external absolute symlink: {symlink.RelativePath} -> {symlink.Target}").ConfigureAwait(false);
                continue;
            }

            if (!File.Exists(absoluteTarget) && !Directory.Exists(absoluteTarget))
            {
                // Preserve broken internal links as-is so import does not silently rewrite them.
                continue;
            }

            var sourceRelativeTarget = Path.GetRelativePath(sourceDirectoryPath, absoluteTarget).Replace('\\', '/');
            var volumeLinkPath = $"/target/{targetRelativePath.TrimEnd('/')}/{symlink.RelativePath.TrimStart('/')}";
            var volumeTargetPath = $"/target/{targetRelativePath.TrimEnd('/')}/{sourceRelativeTarget.TrimStart('/')}";
            var volumeParentPath = NormalizePosixPath(Path.GetDirectoryName(volumeLinkPath)?.Replace('\\', '/') ?? "/target");
            var relativeTarget = ComputeRelativePosixPath(volumeParentPath, NormalizePosixPath(volumeTargetPath));
            operations.Add((NormalizePosixPath(volumeLinkPath), relativeTarget));
        }

        if (operations.Count == 0)
        {
            return 0;
        }

        var commandBuilder = new StringBuilder();
        foreach (var operation in operations)
        {
            commandBuilder.Append("link='");
            commandBuilder.Append(EscapeForSingleQuotedShell(operation.LinkPath));
            commandBuilder.Append("'; ");
            commandBuilder.Append("mkdir -p \"$(dirname \"$link\")\"; ");
            commandBuilder.Append("rm -rf -- \"$link\"; ");
            commandBuilder.Append("ln -sfn -- '");
            commandBuilder.Append(EscapeForSingleQuotedShell(operation.RelativeTarget));
            commandBuilder.Append("' \"$link\"; ");
        }

        var result = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", commandBuilder.ToString()],
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private static List<ImportedSymlink> CollectSymlinksForRelink(string sourceDirectoryPath)
    {
        var symlinks = new List<ImportedSymlink>();
        var stack = new Stack<string>();
        stack.Push(sourceDirectoryPath);
        while (stack.Count > 0)
        {
            var currentDirectory = stack.Pop();
            IEnumerable<string> entries;
            try
            {
                entries = Directory.EnumerateFileSystemEntries(currentDirectory);
            }
            catch (IOException)
            {
                continue;
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (NotSupportedException)
            {
                continue;
            }
            catch (ArgumentException)
            {
                continue;
            }

            foreach (var entry in entries)
            {
                if (IsSymbolicLinkPath(entry))
                {
                    var linkTarget = ReadSymlinkTarget(entry);
                    if (!string.IsNullOrWhiteSpace(linkTarget))
                    {
                        var relativePath = Path.GetRelativePath(sourceDirectoryPath, entry).Replace('\\', '/');
                        symlinks.Add(new ImportedSymlink(relativePath, linkTarget));
                    }

                    continue;
                }

                if (Directory.Exists(entry))
                {
                    stack.Push(entry);
                }
            }
        }

        return symlinks;
    }

    private static string? ReadSymlinkTarget(string path)
    {
        try
        {
            var fileInfo = new FileInfo(path);
            if (!string.IsNullOrWhiteSpace(fileInfo.LinkTarget))
            {
                return fileInfo.LinkTarget;
            }
        }
        catch (IOException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }

        try
        {
            var directoryInfo = new DirectoryInfo(path);
            if (!string.IsNullOrWhiteSpace(directoryInfo.LinkTarget))
            {
                return directoryInfo.LinkTarget;
            }
        }
        catch (IOException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }

        return null;
    }

    private static string NormalizePosixPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return "/";
        }

        var normalized = path.Replace('\\', '/');
        normalized = normalized.Replace("//", "/", StringComparison.Ordinal);
        return string.IsNullOrWhiteSpace(normalized) ? "/" : normalized;
    }

    private static string ComputeRelativePosixPath(string fromDirectory, string toPath)
    {
        var fromParts = NormalizePosixPath(fromDirectory).Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var toParts = NormalizePosixPath(toPath).Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var maxShared = Math.Min(fromParts.Length, toParts.Length);
        var shared = 0;
        while (shared < maxShared && string.Equals(fromParts[shared], toParts[shared], StringComparison.Ordinal))
        {
            shared++;
        }

        var segments = new List<string>();
        for (var index = shared; index < fromParts.Length; index++)
        {
            segments.Add("..");
        }

        for (var index = shared; index < toParts.Length; index++)
        {
            segments.Add(toParts[index]);
        }

        return segments.Count == 0 ? "." : string.Join('/', segments);
    }

    private async Task<int> ApplyManifestPostCopyRulesAsync(
        string volume,
        ManifestEntry entry,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            return 0;
        }

        var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
        if (entry.Flags.Contains('g', StringComparison.Ordinal))
        {
            var gitFilterCode = await ApplyGitConfigFilterAsync(volume, normalizedTarget, verbose, cancellationToken).ConfigureAwait(false);
            if (gitFilterCode != 0)
            {
                return gitFilterCode;
            }
        }

        if (!entry.Flags.Contains('s', StringComparison.Ordinal))
        {
            return 0;
        }

        var chmodMode = entry.Flags.Contains('d', StringComparison.Ordinal) ? "700" : "600";
        var chmodCommand = $"target='/target/{EscapeForSingleQuotedShell(normalizedTarget)}'; " +
                           "if [ -e \"$target\" ]; then chmod " + chmodMode + " \"$target\"; fi; " +
                           "if [ -e \"$target\" ]; then chown 1000:1000 \"$target\" || true; fi";
        var chmodResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", chmodCommand],
            cancellationToken).ConfigureAwait(false);
        if (chmodResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(chmodResult.StandardError))
            {
                await stderr.WriteLineAsync(chmodResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        return 0;
    }

    private async Task<int> ApplyGitConfigFilterAsync(
        string volume,
        string targetRelativePath,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var filterScript = $"target='/target/{EscapeForSingleQuotedShell(targetRelativePath)}'; " +
                           "if [ ! -f \"$target\" ]; then exit 0; fi; " +
                           "tmp=\"$target.tmp\"; " +
                           "awk '\n" +
                           "BEGIN { section=\"\" }\n" +
                           "/^[[:space:]]*\\[[^]]+\\][[:space:]]*$/ {\n" +
                           "  section=$0;\n" +
                           "  gsub(/^[[:space:]]*\\[/, \"\", section);\n" +
                           "  gsub(/\\][[:space:]]*$/, \"\", section);\n" +
                           "  section=tolower(section);\n" +
                           "  print $0;\n" +
                           "  next;\n" +
                           "}\n" +
                           "{\n" +
                           "  lower=tolower($0);\n" +
                           "  if (section==\"credential\" && lower ~ /^[[:space:]]*helper[[:space:]]*=/) next;\n" +
                           "  if ((section==\"commit\" || section==\"tag\") && lower ~ /^[[:space:]]*gpgsign[[:space:]]*=/) next;\n" +
                           "  if (section==\"gpg\" && (lower ~ /^[[:space:]]*program[[:space:]]*=/ || lower ~ /^[[:space:]]*format[[:space:]]*=/)) next;\n" +
                           "  if (section==\"user\" && lower ~ /^[[:space:]]*signingkey[[:space:]]*=/) next;\n" +
                           "  print $0;\n" +
                           "}\n" +
                           "' \"$target\" > \"$tmp\"; " +
                           "mv \"$tmp\" \"$target\"; " +
                           "if ! grep -Eiq \"^[[:space:]]*directory[[:space:]]*=[[:space:]]*/home/agent/workspace[[:space:]]*$\" \"$target\"; then " +
                           "  printf '\\n[safe]\\n\\tdirectory = /home/agent/workspace\\n' >> \"$target\"; " +
                           "fi; " +
                           "chown 1000:1000 \"$target\" || true";

        var filterResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", filterScript],
            cancellationToken).ConfigureAwait(false);
        if (filterResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(filterResult.StandardError))
            {
                await stderr.WriteLineAsync(filterResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        if (verbose)
        {
            await stdout.WriteLineAsync($"[INFO] Applied git filter to {targetRelativePath}").ConfigureAwait(false);
        }

        return 0;
    }

    private async Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var overridesDirectory = Path.Combine(ResolveHomeDirectory(), ".config", "containai", "import-overrides");
        if (!Directory.Exists(overridesDirectory))
        {
            return 0;
        }

        var overrideFiles = Directory.EnumerateFiles(overridesDirectory, "*", SearchOption.AllDirectories)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
        foreach (var file in overrideFiles)
        {
            cancellationToken.ThrowIfCancellationRequested();

            if (IsSymbolicLinkPath(file))
            {
                await stderr.WriteLineAsync($"Skipping override symlink: {file}").ConfigureAwait(false);
                continue;
            }

            var relative = Path.GetRelativePath(overridesDirectory, file).Replace("\\", "/", StringComparison.Ordinal);
            if (!relative.StartsWith('.'))
            {
                relative = "." + relative;
            }

            if (!TryMapSourcePathToTarget(relative, manifestEntries, out var mappedTarget, out var mappedFlags))
            {
                if (verbose)
                {
                    await stderr.WriteLineAsync($"Skipping unmapped override path: {relative}").ConfigureAwait(false);
                }

                continue;
            }

            if (noSecrets && mappedFlags.Contains('s', StringComparison.Ordinal))
            {
                if (verbose)
                {
                    await stderr.WriteLineAsync($"Skipping secret override due to --no-secrets: {relative}").ConfigureAwait(false);
                }

                continue;
            }

            if (dryRun)
            {
                await stdout.WriteLineAsync($"[DRY-RUN] Would apply override {relative} -> {mappedTarget}").ConfigureAwait(false);
                continue;
            }

            var command = $"src='/override/{EscapeForSingleQuotedShell(relative.TrimStart('/'))}'; " +
                          $"dest='/target/{EscapeForSingleQuotedShell(mappedTarget)}'; " +
                          "mkdir -p \"$(dirname \"$dest\")\"; cp -f \"$src\" \"$dest\"; chown 1000:1000 \"$dest\" || true";
            var copy = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/target", "-v", $"{overridesDirectory}:/override:ro", "alpine:3.20", "sh", "-lc", command],
                cancellationToken).ConfigureAwait(false);
            if (copy.ExitCode != 0)
            {
                await stderr.WriteLineAsync(copy.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        return 0;
    }

    private async Task<int> ImportEnvironmentVariablesAsync(
        string volume,
        string workspace,
        string? explicitConfigPath,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : ResolveConfigPath(workspace);
        if (!File.Exists(configPath))
        {
            return 0;
        }

        var configResult = await RunParseTomlAsync(["--file", configPath, "--json"], cancellationToken).ConfigureAwait(false);
        if (configResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(configResult.StandardError))
            {
                await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        if (!string.IsNullOrWhiteSpace(configResult.StandardError))
        {
            await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
        }

        using var configDocument = JsonDocument.Parse(configResult.StandardOutput);
        if (configDocument.RootElement.ValueKind != JsonValueKind.Object ||
            !configDocument.RootElement.TryGetProperty("env", out var envSection))
        {
            return 0;
        }

        if (envSection.ValueKind != JsonValueKind.Object)
        {
            await stderr.WriteLineAsync("[WARN] [env] section must be a table; skipping env import").ConfigureAwait(false);
            return 0;
        }

        var importKeys = new List<string>();
        if (!envSection.TryGetProperty("import", out var importArray))
        {
            await stderr.WriteLineAsync("[WARN] [env].import missing, treating as empty list").ConfigureAwait(false);
        }
        else if (importArray.ValueKind != JsonValueKind.Array)
        {
            await stderr.WriteLineAsync($"[WARN] [env].import must be a list, got {importArray.ValueKind}; treating as empty list").ConfigureAwait(false);
        }
        else
        {
            var itemIndex = 0;
            foreach (var value in importArray.EnumerateArray())
            {
                if (value.ValueKind == JsonValueKind.String)
                {
                    var key = value.GetString();
                    if (!string.IsNullOrWhiteSpace(key))
                    {
                        importKeys.Add(key);
                    }
                }
                else
                {
                    await stderr.WriteLineAsync($"[WARN] [env].import[{itemIndex}] must be a string, got {value.ValueKind}; skipping").ConfigureAwait(false);
                }

                itemIndex++;
            }
        }

        var dedupedImportKeys = new List<string>();
        var seenKeys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var key in importKeys)
        {
            if (seenKeys.Add(key))
            {
                dedupedImportKeys.Add(key);
            }
        }

        if (dedupedImportKeys.Count == 0)
        {
            if (verbose)
            {
                await stdout.WriteLineAsync("[INFO] Empty env allowlist, skipping env import").ConfigureAwait(false);
            }

            return 0;
        }

        var validatedKeys = new List<string>(dedupedImportKeys.Count);
        foreach (var key in dedupedImportKeys)
        {
            if (!EnvVarNameRegex().IsMatch(key))
            {
                await stderr.WriteLineAsync($"[WARN] Invalid env var name in allowlist: {key}").ConfigureAwait(false);
                continue;
            }

            validatedKeys.Add(key);
        }

        if (validatedKeys.Count == 0)
        {
            return 0;
        }

        var workspaceRoot = Path.GetFullPath(ExpandHomePath(workspace));
        var fileVariables = new Dictionary<string, string>(StringComparer.Ordinal);
        if (envSection.TryGetProperty("env_file", out var envFileElement) && envFileElement.ValueKind == JsonValueKind.String)
        {
            var envFile = envFileElement.GetString();
            if (!string.IsNullOrWhiteSpace(envFile))
            {
                var envFileResolution = ResolveEnvFilePath(workspaceRoot, envFile);
                if (envFileResolution.Error is not null)
                {
                    await stderr.WriteLineAsync(envFileResolution.Error).ConfigureAwait(false);
                    return 1;
                }

                if (envFileResolution.Path is not null)
                {
                    var parsed = ParseEnvFile(envFileResolution.Path);
                    foreach (var warning in parsed.Warnings)
                    {
                        await stderr.WriteLineAsync(warning).ConfigureAwait(false);
                    }

                    foreach (var (key, value) in parsed.Values)
                    {
                        if (validatedKeys.Contains(key, StringComparer.Ordinal))
                        {
                            fileVariables[key] = value;
                        }
                    }
                }
            }
        }

        var fromHost = false;
        if (envSection.TryGetProperty("from_host", out var fromHostElement))
        {
            if (fromHostElement.ValueKind == JsonValueKind.True)
            {
                fromHost = true;
            }
            else if (fromHostElement.ValueKind != JsonValueKind.False)
            {
                await stderr.WriteLineAsync("[WARN] [env].from_host must be a boolean; using false").ConfigureAwait(false);
            }
        }
        var merged = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in fileVariables)
        {
            merged[key] = value;
        }

        if (fromHost)
        {
            foreach (var key in validatedKeys)
            {
                var envValue = Environment.GetEnvironmentVariable(key);
                if (envValue is null)
                {
                    await stderr.WriteLineAsync($"[WARN] Missing host env var: {key}").ConfigureAwait(false);
                    continue;
                }

                if (envValue.Contains('\n', StringComparison.Ordinal))
                {
                    await stderr.WriteLineAsync($"[WARN] source=host: key '{key}' skipped (multiline value)").ConfigureAwait(false);
                    continue;
                }

                merged[key] = envValue;
            }
        }

        if (merged.Count == 0)
        {
            return 0;
        }

        if (dryRun)
        {
            foreach (var key in merged.Keys.OrderBy(static value => value, StringComparer.Ordinal))
            {
                await stdout.WriteLineAsync($"[DRY-RUN] env key: {key}").ConfigureAwait(false);
            }

            return 0;
        }

        var builder = new StringBuilder();
        foreach (var key in validatedKeys)
        {
            if (!merged.TryGetValue(key, out var value))
            {
                continue;
            }

            builder.Append(key);
            builder.Append('=');
            builder.Append(value);
            builder.Append('\n');
        }

        var writeCommand = "set -e; target='/mnt/agent-data/.env'; if [ -L \"$target\" ]; then echo '.env target is symlink' >&2; exit 1; fi; " +
                           "tmp='/mnt/agent-data/.env.tmp'; cat > \"$tmp\"; chmod 600 \"$tmp\"; chown 1000:1000 \"$tmp\" || true; mv -f \"$tmp\" \"$target\"";
        var write = await DockerCaptureAsync(
            ["run", "--rm", "-i", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", writeCommand],
            builder.ToString(),
            cancellationToken).ConfigureAwait(false);
        if (write.ExitCode != 0)
        {
            await stderr.WriteLineAsync(write.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

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
            await stderr.WriteLineAsync("Unable to resolve data volume. Use --data-volume.").ConfigureAwait(false);
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
            await stderr.WriteLineAsync(exportResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync(outputPath).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunSyncAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var sourceRoot = ResolveHomeDirectory();
        var destinationRoot = "/mnt/agent-data";
        if (!Directory.Exists(destinationRoot))
        {
            await stderr.WriteLineAsync("sync must run inside a container with /mnt/agent-data").ConfigureAwait(false);
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

        await stdout.WriteLineAsync("Sync complete.").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunLinksAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2 || args[1] is "-h" or "--help")
        {
            await stdout.WriteLineAsync("Usage: cai links <check|fix> [--name <container>] [--workspace <path>] [--dry-run] [--quiet]").ConfigureAwait(false);
            return 0;
        }

        var subcommand = args[1];
        if (!string.Equals(subcommand, "check", StringComparison.Ordinal) &&
            !string.Equals(subcommand, "fix", StringComparison.Ordinal))
        {
            await stderr.WriteLineAsync($"Unknown links subcommand: {subcommand}").ConfigureAwait(false);
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
                        await stderr.WriteLineAsync($"{token} requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    containerName = args[++index];
                    break;
                case "--workspace":
                    if (index + 1 >= args.Count)
                    {
                        await stderr.WriteLineAsync("--workspace requires a value").ConfigureAwait(false);
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
                    await stdout.WriteLineAsync("Usage: cai links <check|fix> [--name <container>] [--workspace <path>] [--dry-run] [--quiet]").ConfigureAwait(false);
                    return 0;
                default:
                    if (!token.StartsWith('-') && string.IsNullOrWhiteSpace(workspace))
                    {
                        workspace = token;
                    }
                    else if (!string.Equals(token, "--", StringComparison.Ordinal))
                    {
                        await stderr.WriteLineAsync($"Unknown links option: {token}").ConfigureAwait(false);
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
            await stderr.WriteLineAsync($"Unable to resolve container for workspace: {resolvedWorkspace}").ConfigureAwait(false);
            return 1;
        }

        var stateResult = await DockerCaptureAsync(
            ["inspect", "--format", "{{.State.Status}}", containerName],
            cancellationToken).ConfigureAwait(false);

        if (stateResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync($"Container not found: {containerName}").ConfigureAwait(false);
            return 1;
        }

        var state = stateResult.StandardOutput.Trim();
        if (string.Equals(subcommand, "check", StringComparison.Ordinal))
        {
            if (!string.Equals(state, "running", StringComparison.Ordinal))
            {
                await stderr.WriteLineAsync($"Container '{containerName}' is not running (state: {state}).").ConfigureAwait(false);
                return 1;
            }
        }
        else if (!string.Equals(state, "running", StringComparison.Ordinal))
        {
            var startResult = await DockerCaptureAsync(["start", containerName], cancellationToken).ConfigureAwait(false);
            if (startResult.ExitCode != 0)
            {
                await stderr.WriteLineAsync($"Failed to start container '{containerName}': {startResult.StandardError.Trim()}").ConfigureAwait(false);
                return 1;
            }
        }

        var command = new List<string>
        {
            "exec",
            containerName,
            "cai",
            "system",
            "link-repair",
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
                await stdout.WriteLineAsync(output).ConfigureAwait(false);
            }
        }

        if (runResult.ExitCode != 0)
        {
            var error = runResult.StandardError.Trim();
            if (!string.IsNullOrWhiteSpace(error))
            {
                await stderr.WriteLineAsync(error).ConfigureAwait(false);
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
            await stdout.WriteLineAsync("Usage: cai update [--dry-run] [--stop-containers] [--force] [--lima-recreate]").ConfigureAwait(false);
            return 0;
        }

        if (!ValidateOptions(args, 1, "--dry-run", "--stop-containers", "--force", "--lima-recreate", "--verbose", "--help", "-h"))
        {
            await stderr.WriteLineAsync("Unknown update option. Use 'cai update --help'.").ConfigureAwait(false);
            return 1;
        }

        if (dryRun)
        {
            await stdout.WriteLineAsync("Would pull latest base image for configured channel.").ConfigureAwait(false);
            if (stopContainers)
            {
                await stdout.WriteLineAsync("Would stop running ContainAI containers before update.").ConfigureAwait(false);
            }
            if (limaRecreate)
            {
                await stdout.WriteLineAsync("Would recreate Lima VM 'containai'.").ConfigureAwait(false);
            }

            await stdout.WriteLineAsync("Would refresh templates and verify installation.").ConfigureAwait(false);
            return 0;
        }

        if (limaRecreate && !OperatingSystem.IsMacOS())
        {
            await stderr.WriteLineAsync("--lima-recreate is only supported on macOS.").ConfigureAwait(false);
            return 1;
        }

        if (limaRecreate)
        {
            await stdout.WriteLineAsync("Recreating Lima VM 'containai'...").ConfigureAwait(false);
            await RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
            var start = await RunProcessCaptureAsync("limactl", ["start", "containai"], cancellationToken).ConfigureAwait(false);
            if (start.ExitCode != 0)
            {
                await stderr.WriteLineAsync(start.StandardError.Trim()).ConfigureAwait(false);
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
            await stderr.WriteLineAsync("Update completed with validation warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Update complete.").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunRefreshAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var showHelp = args.Contains("--help", StringComparer.Ordinal) || args.Contains("-h", StringComparer.Ordinal);
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai refresh [--rebuild] [--verbose]").ConfigureAwait(false);
            return 0;
        }

        if (!ValidateOptions(args, 1, "--rebuild", "--verbose", "--help", "-h"))
        {
            await stderr.WriteLineAsync("Unknown refresh option. Use 'cai refresh --help'.").ConfigureAwait(false);
            return 1;
        }

        var channel = await ResolveChannelAsync(cancellationToken).ConfigureAwait(false);
        var baseImage = string.Equals(channel, "nightly", StringComparison.Ordinal)
            ? "ghcr.io/novotnyllc/containai:nightly"
            : "ghcr.io/novotnyllc/containai:latest";

        await stdout.WriteLineAsync($"Pulling {baseImage}...").ConfigureAwait(false);
        var pull = await DockerCaptureAsync(["pull", baseImage], cancellationToken).ConfigureAwait(false);
        if (pull.ExitCode != 0)
        {
            await stderr.WriteLineAsync(pull.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        if (!args.Contains("--rebuild", StringComparer.Ordinal))
        {
            await stdout.WriteLineAsync("Refresh complete.").ConfigureAwait(false);
            return 0;
        }

        var templatesRoot = ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            await stderr.WriteLineAsync($"Template directory not found: {templatesRoot}").ConfigureAwait(false);
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
                await stderr.WriteLineAsync($"Template rebuild failed for '{templateName}': {build.StandardError.Trim()}").ConfigureAwait(false);
                continue;
            }

            await stdout.WriteLineAsync($"Rebuilt template '{templateName}' as {imageName}").ConfigureAwait(false);
        }

        return failures == 0 ? 0 : 1;
    }

    private async Task<int> RunUninstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var showHelp = args.Contains("--help", StringComparer.Ordinal) || args.Contains("-h", StringComparer.Ordinal);
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai uninstall [--dry-run] [--containers] [--volumes] [--force]").ConfigureAwait(false);
            return 0;
        }

        if (!ValidateOptions(args, 1, "--dry-run", "--containers", "--volumes", "--force", "--verbose", "--help", "-h"))
        {
            await stderr.WriteLineAsync("Unknown uninstall option. Use 'cai uninstall --help'.").ConfigureAwait(false);
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
                await stdout.WriteLineAsync($"Would remove Docker context: {context}").ConfigureAwait(false);
                continue;
            }

            await DockerCaptureAsync(["context", "rm", "-f", context], cancellationToken).ConfigureAwait(false);
        }

        if (!removeContainers)
        {
            await stdout.WriteLineAsync("Uninstall complete (contexts cleaned). Use --containers/--volumes for full cleanup.").ConfigureAwait(false);
            return 0;
        }

        var list = await DockerCaptureAsync(["ps", "-aq", "--filter", "label=containai.managed=true"], cancellationToken).ConfigureAwait(false);
        if (list.ExitCode != 0)
        {
            await stderr.WriteLineAsync(list.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        var containerIds = list.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var volumeNames = new HashSet<string>(StringComparer.Ordinal);
        foreach (var containerId in containerIds)
        {
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove container {containerId}").ConfigureAwait(false);
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
                await stdout.WriteLineAsync($"Would remove volume {volume}").ConfigureAwait(false);
                continue;
            }

            await DockerCaptureAsync(["volume", "rm", volume], cancellationToken).ConfigureAwait(false);
        }

        await stdout.WriteLineAsync("Uninstall complete.").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunConfigAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2)
        {
            await stderr.WriteLineAsync("Usage: cai config <list|get|set|unset|resolve-volume> [options]").ConfigureAwait(false);
            return 1;
        }

        var parsed = ParseConfigOptions(args.Skip(1).ToArray());
        if (parsed.Error is not null)
        {
            await stderr.WriteLineAsync(parsed.Error).ConfigureAwait(false);
            return 1;
        }

        if (string.Equals(parsed.Action, "resolve-volume", StringComparison.Ordinal))
        {
            return await ConfigResolveVolumeAsync(parsed, cancellationToken).ConfigureAwait(false);
        }

        var configPath = ResolveConfigPath(parsed.Workspace);
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

    private async Task<int> RunManifestAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2 || args[1] is "-h" or "--help")
        {
            await stdout.WriteLineAsync("Usage: cai manifest <parse|generate|apply|check> ...").ConfigureAwait(false);
            return 0;
        }

        return args[1] switch
        {
            "parse" => await RunManifestParseAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false),
            "generate" => await RunManifestGenerateAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false),
            "apply" => await RunManifestApplyAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false),
            "check" => await RunManifestCheckAsync(args.Skip(2).ToArray(), cancellationToken).ConfigureAwait(false),
            _ => await WriteManifestSubcommandErrorAsync(args[1]).ConfigureAwait(false),
        };
    }

    private async Task<int> WriteManifestSubcommandErrorAsync(string subcommand)
    {
        await stderr.WriteLineAsync($"Unknown manifest subcommand: {subcommand}").ConfigureAwait(false);
        await stderr.WriteLineAsync("Usage: cai manifest <parse|generate|apply|check> ...").ConfigureAwait(false);
        return 1;
    }

    private async Task<int> RunManifestParseAsync(string[] args, CancellationToken cancellationToken)
    {
        var includeDisabled = false;
        var emitSourceFile = false;
        string? manifestPath = null;

        foreach (var token in args)
        {
            switch (token)
            {
                case "--include-disabled":
                    includeDisabled = true;
                    break;
                case "--emit-source-file":
                    emitSourceFile = true;
                    break;
                default:
                    if (token.StartsWith('-'))
                    {
                        await stderr.WriteLineAsync($"ERROR: unknown option: {token}").ConfigureAwait(false);
                        return 1;
                    }

                    if (manifestPath is not null)
                    {
                        await stderr.WriteLineAsync("ERROR: only one manifest path is supported").ConfigureAwait(false);
                        return 1;
                    }

                    manifestPath = token;
                    break;
            }
        }

        if (string.IsNullOrWhiteSpace(manifestPath))
        {
            await stderr.WriteLineAsync("ERROR: manifest file or directory required").ConfigureAwait(false);
            return 1;
        }

        try
        {
            var parsed = ManifestTomlParser.Parse(manifestPath, includeDisabled, emitSourceFile);
            foreach (var entry in parsed)
            {
                cancellationToken.ThrowIfCancellationRequested();
                await stdout.WriteLineAsync(entry.ToString()).ConfigureAwait(false);
            }

            return 0;
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunManifestGenerateAsync(string[] args, CancellationToken cancellationToken)
    {
        if (args.Length < 2)
        {
            await stderr.WriteLineAsync("ERROR: usage: cai manifest generate container-link-spec <manifest_path_or_dir> [output_path]").ConfigureAwait(false);
            return 1;
        }

        var kind = args[0];
        var manifestPath = args[1];
        var outputPath = args.Length >= 3 ? args[2] : null;

        try
        {
            var generated = kind switch
            {
                "container-link-spec" => ManifestGenerators.GenerateContainerLinkSpec(manifestPath),
                _ => throw new InvalidOperationException($"unknown generator kind: {kind}"),
            };

            if (!string.IsNullOrWhiteSpace(outputPath))
            {
                var outputDirectory = Path.GetDirectoryName(Path.GetFullPath(outputPath));
                if (!string.IsNullOrWhiteSpace(outputDirectory))
                {
                    Directory.CreateDirectory(outputDirectory);
                }

                await File.WriteAllTextAsync(outputPath, generated.Content, cancellationToken).ConfigureAwait(false);
                await stderr.WriteLineAsync($"Generated: {outputPath} ({generated.Count} links)").ConfigureAwait(false);

                return 0;
            }

            await stdout.WriteAsync(generated.Content).ConfigureAwait(false);
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunManifestApplyAsync(string[] args, CancellationToken cancellationToken)
    {
        if (args.Length < 2)
        {
            await stderr.WriteLineAsync("ERROR: usage: cai manifest apply <container-links|init-dirs|agent-shims> <manifest_path_or_dir> [options]").ConfigureAwait(false);
            return 1;
        }

        var kind = args[0];
        var manifestPath = args[1];
        var dataDir = "/mnt/agent-data";
        var homeDir = "/home/agent";
        var shimDir = "/opt/containai/user-agent-shims";
        var caiBinaryPath = "/usr/local/bin/cai";

        for (var index = 2; index < args.Length; index++)
        {
            var token = args[index];
            if (token is "-h" or "--help")
            {
                await stdout.WriteLineAsync("Usage: cai manifest apply <container-links|init-dirs|agent-shims> <manifest_path_or_dir> [--data-dir <path>] [--home-dir <path>] [--shim-dir <path>] [--cai-binary <path>]").ConfigureAwait(false);
                return 0;
            }

            if (token == "--data-dir")
            {
                if (index + 1 >= args.Length || args[index + 1].StartsWith('-'))
                {
                    await stderr.WriteLineAsync("ERROR: --data-dir requires a value").ConfigureAwait(false);
                    return 1;
                }

                dataDir = args[++index];
                continue;
            }

            if (token.StartsWith("--data-dir=", StringComparison.Ordinal))
            {
                dataDir = token[11..];
                continue;
            }

            if (token == "--home-dir")
            {
                if (index + 1 >= args.Length || args[index + 1].StartsWith('-'))
                {
                    await stderr.WriteLineAsync("ERROR: --home-dir requires a value").ConfigureAwait(false);
                    return 1;
                }

                homeDir = args[++index];
                continue;
            }

            if (token.StartsWith("--home-dir=", StringComparison.Ordinal))
            {
                homeDir = token[11..];
                continue;
            }

            if (token == "--shim-dir")
            {
                if (index + 1 >= args.Length || args[index + 1].StartsWith('-'))
                {
                    await stderr.WriteLineAsync("ERROR: --shim-dir requires a value").ConfigureAwait(false);
                    return 1;
                }

                shimDir = args[++index];
                continue;
            }

            if (token.StartsWith("--shim-dir=", StringComparison.Ordinal))
            {
                shimDir = token[11..];
                continue;
            }

            if (token == "--cai-binary")
            {
                if (index + 1 >= args.Length || args[index + 1].StartsWith('-'))
                {
                    await stderr.WriteLineAsync("ERROR: --cai-binary requires a value").ConfigureAwait(false);
                    return 1;
                }

                caiBinaryPath = args[++index];
                continue;
            }

            if (token.StartsWith("--cai-binary=", StringComparison.Ordinal))
            {
                caiBinaryPath = token[13..];
                continue;
            }

            await stderr.WriteLineAsync($"ERROR: unknown option: {token}").ConfigureAwait(false);
            return 1;
        }

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var applied = kind switch
            {
                "container-links" => ManifestApplier.ApplyContainerLinks(manifestPath, homeDir, dataDir),
                "init-dirs" => ManifestApplier.ApplyInitDirs(manifestPath, dataDir),
                "agent-shims" => ManifestApplier.ApplyAgentShims(manifestPath, shimDir, caiBinaryPath),
                _ => throw new InvalidOperationException($"unknown apply kind: {kind}"),
            };

            await stderr.WriteLineAsync($"Applied {kind}: {applied}").ConfigureAwait(false);
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunManifestCheckAsync(string[] args, CancellationToken cancellationToken)
    {
        string? manifestDirectory = null;

        for (var index = 0; index < args.Length; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "-h":
                case "--help":
                    await stdout.WriteLineAsync("Usage: cai manifest check [--manifest-dir <path>]").ConfigureAwait(false);
                    return 0;
                case "--manifest-dir":
                    if (index + 1 >= args.Length || args[index + 1].StartsWith('-'))
                    {
                        await stderr.WriteLineAsync("ERROR: --manifest-dir requires a value").ConfigureAwait(false);
                        return 1;
                    }

                    manifestDirectory = args[++index];
                    break;
                default:
                    if (token.StartsWith("--manifest-dir=", StringComparison.Ordinal))
                    {
                        manifestDirectory = token[15..];
                        break;
                    }

                    if (token.StartsWith('-'))
                    {
                        await stderr.WriteLineAsync($"ERROR: unknown option: {token}").ConfigureAwait(false);
                        return 1;
                    }

                    if (manifestDirectory is not null)
                    {
                        await stderr.WriteLineAsync("ERROR: only one manifest directory can be specified").ConfigureAwait(false);
                        return 1;
                    }

                    manifestDirectory = token;
                    break;
            }
        }

        manifestDirectory = ResolveManifestDirectory(manifestDirectory);
        if (!Directory.Exists(manifestDirectory))
        {
            await stderr.WriteLineAsync($"ERROR: manifest directory not found: {manifestDirectory}").ConfigureAwait(false);
            return 1;
        }

        var manifestFiles = Directory
            .EnumerateFiles(manifestDirectory, "*.toml", SearchOption.TopDirectoryOnly)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
        if (manifestFiles.Length == 0)
        {
            await stderr.WriteLineAsync($"ERROR: no .toml files found in directory: {manifestDirectory}").ConfigureAwait(false);
            return 1;
        }

        foreach (var file in manifestFiles)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ManifestTomlParser.Parse(file, includeDisabled: true, includeSourceFile: false);
        }

        var linkSpec = ManifestGenerators.GenerateContainerLinkSpec(manifestDirectory);
        var initProbeDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-check-{Guid.NewGuid():N}");
        var initApplied = 0;
        try
        {
            initApplied = ManifestApplier.ApplyInitDirs(manifestDirectory, initProbeDir);
        }
        finally
        {
            if (Directory.Exists(initProbeDir))
            {
                Directory.Delete(initProbeDir, recursive: true);
            }
        }

        if (initApplied <= 0)
        {
            await stderr.WriteLineAsync("ERROR: init-dir apply produced no operations").ConfigureAwait(false);
            return 1;
        }

        try
        {
            using var document = JsonDocument.Parse(linkSpec.Content);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("links", out var links) ||
                links.ValueKind != JsonValueKind.Array)
            {
                await stderr.WriteLineAsync("ERROR: generated link spec appears invalid").ConfigureAwait(false);
                return 1;
            }
        }
        catch (JsonException)
        {
            await stderr.WriteLineAsync("ERROR: generated link spec is not valid JSON").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Manifest consistency check passed.").ConfigureAwait(false);
        return 0;
    }

    private static string ResolveImportManifestDirectory()
    {
        var candidates = ResolveManifestDirectoryCandidates();
        foreach (var candidate in candidates)
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException($"manifest directory not found; tried: {string.Join(", ", candidates)}");
    }

    private static string ResolveManifestDirectory(string? userProvidedPath)
    {
        if (!string.IsNullOrWhiteSpace(userProvidedPath))
        {
            return Path.GetFullPath(ExpandHomePath(userProvidedPath));
        }

        var candidates = ResolveManifestDirectoryCandidates();
        foreach (var candidate in candidates)
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        return candidates[0];
    }

    private static string[] ResolveManifestDirectoryCandidates()
    {
        var candidates = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        static void AddCandidate(ICollection<string> target, ISet<string> seenSet, string? path)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                return;
            }

            var fullPath = Path.GetFullPath(path);
            if (seenSet.Add(fullPath))
            {
                target.Add(fullPath);
            }
        }

        var installRoot = InstallMetadata.ResolveInstallDirectory();
        AddCandidate(candidates, seen, Path.Combine(installRoot, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(installRoot, "src", "manifests"));

        var appBase = Path.GetFullPath(AppContext.BaseDirectory);
        AddCandidate(candidates, seen, Path.Combine(appBase, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "..", "manifests"));

        var current = Directory.GetCurrentDirectory();
        AddCandidate(candidates, seen, Path.Combine(current, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(current, "src", "manifests"));

        AddCandidate(candidates, seen, "/opt/containai/manifests");
        return candidates.ToArray();
    }

    private async Task<int> ConfigListAsync(string configPath, CancellationToken cancellationToken)
    {
        var parseResult = await RunParseTomlAsync(["--file", configPath, "--json"], cancellationToken).ConfigureAwait(false);
        if (parseResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync(parseResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync(parseResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> ConfigGetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key))
        {
            await stderr.WriteLineAsync("config get requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
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
                await stdout.WriteLineAsync(wsValue.ToString()).ConfigureAwait(false);
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

        await stdout.WriteLineAsync(getResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> ConfigSetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key) || parsed.Value is null)
        {
            await stderr.WriteLineAsync("config set requires <key> <value>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
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
            await stderr.WriteLineAsync(setResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> ConfigUnsetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key))
        {
            await stderr.WriteLineAsync("config unset requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
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
            await stderr.WriteLineAsync(unsetResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> ConfigResolveVolumeAsync(ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        var workspace = string.IsNullOrWhiteSpace(parsed.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(ExpandHomePath(parsed.Workspace));

        var volume = await ResolveDataVolumeAsync(workspace, parsed.Key, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            return 1;
        }

        await stdout.WriteLineAsync(volume).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunTemplateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2 || args[1] is "-h" or "--help")
        {
            await stdout.WriteLineAsync("Usage: cai template upgrade [name] [--dry-run]").ConfigureAwait(false);
            return 0;
        }

        if (!string.Equals(args[1], "upgrade", StringComparison.Ordinal))
        {
            await stderr.WriteLineAsync($"Unknown template subcommand: {args[1]}").ConfigureAwait(false);
            return 1;
        }

        var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
        var templateName = args.Skip(2).FirstOrDefault(static token => !token.StartsWith('-'));

        var templatesRoot = ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            await stderr.WriteLineAsync($"Template directory not found: {templatesRoot}").ConfigureAwait(false);
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
            if (!TemplateUtilities.TryUpgradeDockerfile(content, out var updated))
            {
                continue;
            }

            changedCount++;
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would upgrade {dockerfile}").ConfigureAwait(false);
                continue;
            }

            await File.WriteAllTextAsync(dockerfile, updated, cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync($"Upgraded {dockerfile}").ConfigureAwait(false);
        }

        if (changedCount == 0)
        {
            await stdout.WriteLineAsync("No template changes required.").ConfigureAwait(false);
        }

        return 0;
    }

    private async Task<int> RunSshAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (args.Count < 2 || args[1] is "-h" or "--help")
        {
            await stdout.WriteLineAsync("Usage: cai ssh cleanup [--dry-run]").ConfigureAwait(false);
            return 0;
        }

        if (!string.Equals(args[1], "cleanup", StringComparison.Ordinal))
        {
            await stderr.WriteLineAsync($"Unknown ssh subcommand: {args[1]}").ConfigureAwait(false);
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
                await stdout.WriteLineAsync($"Would remove {file}").ConfigureAwait(false);
                continue;
            }

            File.Delete(file);
            await stdout.WriteLineAsync($"Removed {file}").ConfigureAwait(false);
        }

        if (removed == 0)
        {
            await stdout.WriteLineAsync("No stale SSH configs found.").ConfigureAwait(false);
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
            await stderr.WriteLineAsync(stopValidationError).ConfigureAwait(false);
            return 1;
        }

        if (stopAll && !string.IsNullOrWhiteSpace(containerName))
        {
            await stderr.WriteLineAsync("--all and --container are mutually exclusive").ConfigureAwait(false);
            return 1;
        }

        if (stopAll && exportFirst)
        {
            await stderr.WriteLineAsync("--export and --all are mutually exclusive").ConfigureAwait(false);
            return 1;
        }

        var targets = new List<(string Context, string Container)>();
        if (!string.IsNullOrWhiteSpace(containerName))
        {
            var contexts = await FindContainerContextsAsync(containerName, cancellationToken).ConfigureAwait(false);
            if (contexts.Count == 0)
            {
                await stderr.WriteLineAsync($"Container not found: {containerName}").ConfigureAwait(false);
                return 1;
            }

            if (contexts.Count > 1)
            {
                await stderr.WriteLineAsync($"Container '{containerName}' exists in multiple contexts: {string.Join(", ", contexts)}").ConfigureAwait(false);
                return 1;
            }

            targets.Add((contexts[0], containerName));
        }
        else if (stopAll)
        {
            foreach (var context in await GetAvailableContextsAsync(cancellationToken).ConfigureAwait(false))
            {
                var list = await DockerCaptureForContextAsync(
                    context,
                    ["ps", "-aq", "--filter", "label=containai.managed=true"],
                    cancellationToken).ConfigureAwait(false);
                if (list.ExitCode != 0)
                {
                    continue;
                }

                foreach (var container in list.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    targets.Add((context, container));
                }
            }
        }
        else
        {
            var workspace = Path.GetFullPath(Directory.GetCurrentDirectory());
            var workspaceContainer = await ResolveWorkspaceContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(workspaceContainer))
            {
                await stderr.WriteLineAsync("Usage: cai stop --all | --container <name> [--remove]").ConfigureAwait(false);
                return 1;
            }

            var contexts = await FindContainerContextsAsync(workspaceContainer, cancellationToken).ConfigureAwait(false);
            if (contexts.Count == 0)
            {
                await stderr.WriteLineAsync($"Container not found: {workspaceContainer}").ConfigureAwait(false);
                return 1;
            }

            if (contexts.Count > 1)
            {
                await stderr.WriteLineAsync($"Container '{workspaceContainer}' exists in multiple contexts: {string.Join(", ", contexts)}").ConfigureAwait(false);
                return 1;
            }

            targets.Add((contexts[0], workspaceContainer));
        }

        if (targets.Count == 0)
        {
            await stdout.WriteLineAsync("No ContainAI containers found.").ConfigureAwait(false);
            return 0;
        }

        var failures = 0;
        foreach (var target in targets)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (exportFirst)
            {
                var exportExitCode = await RunExportAsync(["export", "--container", target.Container], cancellationToken).ConfigureAwait(false);
                if (exportExitCode != 0)
                {
                    failures++;
                    await stderr.WriteLineAsync($"Failed to export data volume for container: {target.Container}").ConfigureAwait(false);
                    if (!force)
                    {
                        continue;
                    }
                }
            }

            var stopResult = await DockerCaptureForContextAsync(target.Context, ["stop", target.Container], cancellationToken).ConfigureAwait(false);
            if (stopResult.ExitCode != 0)
            {
                failures++;
                await stderr.WriteLineAsync($"Failed to stop container: {target.Container}").ConfigureAwait(false);
                if (!force)
                {
                    continue;
                }
            }

            if (remove)
            {
                var removeResult = await DockerCaptureForContextAsync(target.Context, ["rm", "-f", target.Container], cancellationToken).ConfigureAwait(false);
                if (removeResult.ExitCode != 0)
                {
                    failures++;
                    await stderr.WriteLineAsync($"Failed to remove container: {target.Container}").ConfigureAwait(false);
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
            await stderr.WriteLineAsync($"Invalid --age value: {ageValue}").ConfigureAwait(false);
            return 1;
        }

        var candidates = await DockerCaptureAsync(
            ["ps", "-aq", "--filter", "label=containai.managed=true", "--filter", "status=exited", "--filter", "status=created"],
            cancellationToken).ConfigureAwait(false);

        if (candidates.ExitCode != 0)
        {
            await stderr.WriteLineAsync(candidates.StandardError.Trim()).ConfigureAwait(false);
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
                await stderr.WriteLineAsync("gc requires --force in non-interactive mode.").ConfigureAwait(false);
                return 1;
            }

            await stdout.WriteLineAsync($"About to remove {pruneCandidates.Count} containers. Continue? [y/N]").ConfigureAwait(false);
            var response = (Console.ReadLine() ?? string.Empty).Trim();
            if (!response.Equals("y", StringComparison.OrdinalIgnoreCase) &&
                !response.Equals("yes", StringComparison.OrdinalIgnoreCase))
            {
                await stdout.WriteLineAsync("Aborted.").ConfigureAwait(false);
                return 1;
            }
        }

        foreach (var containerId in pruneCandidates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove container {containerId}").ConfigureAwait(false);
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
                await stderr.WriteLineAsync("Use --force with --images to remove images.").ConfigureAwait(false);
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
                        await stdout.WriteLineAsync($"Would remove image {reference}").ConfigureAwait(false);
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

    private static async Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
    {
        var result = await DockerRunAsync(["inspect", "--type", "container", containerName], cancellationToken).ConfigureAwait(false);
        return result == 0;
    }

    private static async Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        return result.ExitCode;
    }

    private static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
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

    private static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, string standardInput, CancellationToken cancellationToken)
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

    private static async Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
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

    private static async Task<List<string>> FindContainerContextsAsync(string containerName, CancellationToken cancellationToken)
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

    private static async Task<List<string>> GetAvailableContextsAsync(CancellationToken cancellationToken)
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

    private static async Task<ProcessResult> DockerCaptureForContextAsync(string context, IReadOnlyList<string> args, CancellationToken cancellationToken)
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

    private static bool IsExecutableOnPath(string fileName)
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

    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    private static string ResolveUserConfigPath()
    {
        var home = ResolveHomeDirectory();
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai", ConfigFileNames[0]);
    }

    private static string? TryFindExistingUserConfigPath()
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

    private static string ResolveConfigPath(string? workspacePath)
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

    private static string? TryFindWorkspaceConfigPath(string? workspacePath)
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

    private static string ResolveTemplatesDirectory()
    {
        var home = ResolveHomeDirectory();
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai", "templates");
    }

    private static async Task<string> ResolveChannelAsync(CancellationToken cancellationToken)
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

        var result = await RunParseTomlAsync(["--file", configPath, "--key", "image.channel"], cancellationToken).ConfigureAwait(false);

        if (result.ExitCode != 0)
        {
            return "stable";
        }

        return string.Equals(result.StandardOutput.Trim(), "nightly", StringComparison.OrdinalIgnoreCase)
            ? "nightly"
            : "stable";
    }

    private static async Task<string?> ResolveDataVolumeAsync(string workspace, string? explicitVolume, CancellationToken cancellationToken)
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

    private static async Task<string?> ResolveDataVolumeFromContainerAsync(string containerName, string? explicitVolume, CancellationToken cancellationToken)
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

    private static async Task<ProcessResult> RunParseTomlAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = TomlCommandProcessor.Execute(args);
        return await Task.FromResult(new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError)).ConfigureAwait(false);
    }

    private static string NormalizeConfigKey(string key) => string.Equals(key, "agent", StringComparison.Ordinal)
            ? "agent.default"
            : key;

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
            "resolve-volume" => new ParsedConfigCommand(action, tail.Count >= 2 ? tail[1] : null, null, false, workspace, null),
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
                if (index + 1 >= args.Count || args[index + 1].StartsWith('-'))
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
            if (!token.StartsWith('-'))
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

    private static string GetRootHelpText() => """
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
  manifest      Parse manifests and generate derived artifacts
  template      Manage templates
  update        Update ContainAI installation
  refresh       Pull latest base image and optionally rebuild template
  uninstall     Remove ContainAI system components
  completion    Resolve completion suggestions
  version       Show version
  help          Show this help message
  system        Internal container runtime commands
  acp           ACP proxy tooling

Examples:
  cai
  cai shell
  cai exec ls -la
  cai stop --all
  cai doctor
""";

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

    private static bool IsSymbolicLinkPath(string path)
    {
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    private static bool TryMapSourcePathToTarget(
        string sourceRelativePath,
        IReadOnlyList<ManifestEntry> entries,
        out string targetRelativePath,
        out string flags)
    {
        targetRelativePath = string.Empty;
        flags = string.Empty;

        var normalizedSource = sourceRelativePath.Replace("\\", "/", StringComparison.Ordinal);
        ManifestEntry? match = null;
        var bestLength = -1;
        string? suffix = null;

        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry.Source))
            {
                continue;
            }

            var entrySource = entry.Source.Replace("\\", "/", StringComparison.Ordinal).TrimEnd('/');
            var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
            if (isDirectory)
            {
                var prefix = $"{entrySource}/";
                if (!normalizedSource.StartsWith(prefix, StringComparison.Ordinal) &&
                    !string.Equals(normalizedSource, entrySource, StringComparison.Ordinal))
                {
                    continue;
                }

                if (entrySource.Length <= bestLength)
                {
                    continue;
                }

                match = entry;
                bestLength = entrySource.Length;
                suffix = string.Equals(normalizedSource, entrySource, StringComparison.Ordinal)
                    ? string.Empty
                    : normalizedSource[prefix.Length..];
                continue;
            }

            if (!string.Equals(normalizedSource, entrySource, StringComparison.Ordinal))
            {
                continue;
            }

            if (entrySource.Length <= bestLength)
            {
                continue;
            }

            match = entry;
            bestLength = entrySource.Length;
            suffix = null;
        }

        if (match is null)
        {
            return false;
        }

        flags = match.Value.Flags;
        targetRelativePath = string.IsNullOrEmpty(suffix)
            ? match.Value.Target
            : $"{match.Value.Target.TrimEnd('/')}/{suffix}";
        return true;
    }

    private static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\"'\"'", StringComparison.Ordinal);

    private static EnvFilePathResolution ResolveEnvFilePath(string workspaceRoot, string envFile)
    {
        if (Path.IsPathRooted(envFile))
        {
            return new EnvFilePathResolution(null, $"env_file path rejected: absolute paths are not allowed (must be workspace-relative): {envFile}");
        }

        var candidate = Path.GetFullPath(Path.Combine(workspaceRoot, envFile));
        var workspacePrefix = workspaceRoot.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal)
            ? workspaceRoot
            : workspaceRoot + Path.DirectorySeparatorChar;
        if (!candidate.StartsWith(workspacePrefix, StringComparison.Ordinal) && !string.Equals(candidate, workspaceRoot, StringComparison.Ordinal))
        {
            return new EnvFilePathResolution(null, $"env_file path rejected: outside workspace boundary: {envFile}");
        }

        if (!File.Exists(candidate))
        {
            return new EnvFilePathResolution(null, null);
        }

        if (IsSymbolicLinkPath(candidate))
        {
            return new EnvFilePathResolution(null, $"env_file is a symlink (rejected): {candidate}");
        }

        return new EnvFilePathResolution(candidate, null);
    }

    private static ParsedEnvFile ParseEnvFile(string filePath)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        var warnings = new List<string>();
        using var reader = new StreamReader(filePath);
        var lineNumber = 0;
        while (reader.ReadLine() is { } line)
        {
            lineNumber++;
            var normalized = line.TrimEnd('\r');
            if (string.IsNullOrWhiteSpace(normalized) || normalized.StartsWith('#'))
            {
                continue;
            }

            if (normalized.StartsWith("export ", StringComparison.Ordinal))
            {
                normalized = normalized[7..].TrimStart();
            }

            var separatorIndex = normalized.IndexOf('=', StringComparison.Ordinal);
            if (separatorIndex <= 0)
            {
                warnings.Add($"[WARN] line {lineNumber}: no = found - skipping");
                continue;
            }

            var key = normalized[..separatorIndex];
            var value = normalized[(separatorIndex + 1)..];
            if (!EnvVarNameRegex().IsMatch(key))
            {
                warnings.Add($"[WARN] line {lineNumber}: key '{key}' invalid format - skipping");
                continue;
            }

            if (value.StartsWith('"') && !value[1..].Contains('"', StringComparison.Ordinal))
            {
                warnings.Add($"[WARN] line {lineNumber}: key '{key}' skipped (multiline value)");
                continue;
            }

            if (value.StartsWith('\'') && !value[1..].Contains('\'', StringComparison.Ordinal))
            {
                warnings.Add($"[WARN] line {lineNumber}: key '{key}' skipped (multiline value)");
                continue;
            }

            values[key] = value;
        }

        return new ParsedEnvFile(values, warnings);
    }

    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_]*$", RegexOptions.CultureInvariant)]
    private static partial Regex EnvVarNameRegex();

    private static async Task<bool> CommandSucceedsAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private async Task<string?> ResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var configPath = ResolveConfigPath(workspace);
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
            await stderr.WriteLineAsync($"Multiple containers found for workspace: {workspace}").ConfigureAwait(false);
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

    private static async Task CopyDirectoryAsync(string sourceDirectory, string destinationDirectory, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(destinationDirectory);

        foreach (var sourceFile in Directory.EnumerateFiles(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationFile = Path.Combine(destinationDirectory, Path.GetFileName(sourceFile));
            using var sourceStream = File.OpenRead(sourceFile);
            using var destinationStream = File.Create(destinationFile);
            await sourceStream.CopyToAsync(destinationStream, cancellationToken).ConfigureAwait(false);
        }

        foreach (var sourceSubdirectory in Directory.EnumerateDirectories(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationSubdirectory = Path.Combine(destinationDirectory, Path.GetFileName(sourceSubdirectory));
            await CopyDirectoryAsync(sourceSubdirectory, destinationSubdirectory, cancellationToken).ConfigureAwait(false);
        }
    }

    private static async Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        try
        {
            var result = await CliWrapProcessRunner
                .RunCaptureAsync(fileName, arguments, cancellationToken, standardInput: standardInput)
                .ConfigureAwait(false);

            return new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(1, string.Empty, ex.Message);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(1, string.Empty, ex.Message);
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(1, string.Empty, ex.Message);
        }
    }

    private static async Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        try
        {
            return await CliWrapProcessRunner.RunInteractiveAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
    }

    private readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);

    private readonly record struct ParsedImportOptions(
        string? SourcePath,
        string? ExplicitVolume,
        string? Workspace,
        string? ConfigPath,
        bool DryRun,
        bool NoExcludes,
        bool NoSecrets,
        bool Verbose,
        string? Error)
    {
        public static ParsedImportOptions WithError(string error)
            => new(null, null, null, null, false, false, false, false, error);
    }

    private readonly record struct AdditionalImportPath(
        string SourcePath,
        string TargetPath,
        bool IsDirectory,
        bool ApplyPrivFilter);

    private readonly record struct ImportedSymlink(
        string RelativePath,
        string Target);

    private readonly record struct EnvFilePathResolution(string? Path, string? Error);
    private readonly record struct ParsedEnvFile(
        IReadOnlyDictionary<string, string> Values,
        IReadOnlyList<string> Warnings);

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
