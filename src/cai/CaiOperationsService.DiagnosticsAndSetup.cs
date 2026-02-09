using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{
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

    private async Task<int> RunVersionCoreAsync(bool json, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
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

    private async Task<int> RunDoctorCoreAsync(
        bool outputJson,
        bool buildTemplates,
        bool resetLima,
        CancellationToken cancellationToken)
    {
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

    private async Task<int> RunSetupCoreAsync(
        bool dryRun,
        bool verbose,
        bool skipTemplates,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai setup [--dry-run] [--verbose] [--skip-templates]").ConfigureAwait(false);
            return 0;
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

        var doctorExitCode = await RunDoctorCoreAsync(outputJson: false, buildTemplates: false, resetLima: false, cancellationToken).ConfigureAwait(false);
        if (doctorExitCode != 0)
        {
            await stderr.WriteLineAsync("Setup completed with warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Setup complete.").ConfigureAwait(false);
        return doctorExitCode;
    }

    private async Task<int> RunDoctorFixCoreAsync(
        bool fixAll,
        bool dryRun,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
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
            _ = await RunSshCleanupCoreAsync(dryRun: false, cancellationToken).ConfigureAwait(false);
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

}
