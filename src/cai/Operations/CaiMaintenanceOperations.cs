using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiMaintenanceOperations : CaiRuntimeSupport
{
    private readonly ContainerLinkRepairService containerLinkRepairService;
    private readonly Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync;

    public CaiMaintenanceOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ContainerLinkRepairService containerLinkRepairService,
        Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync)
        : base(standardOutput, standardError)
    {
        this.containerLinkRepairService = containerLinkRepairService;
        this.runDoctorAsync = runDoctorAsync;
    }

    public async Task<int> RunExportAsync(
        string? output,
        string? explicitVolume,
        string? container,
        string? workspace,
        CancellationToken cancellationToken)
    {
        workspace ??= Directory.GetCurrentDirectory();
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

    public async Task<int> RunSyncAsync(CancellationToken cancellationToken)
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

    public async Task<int> RunLinksAsync(
        string subcommand,
        string? containerName,
        string? workspace,
        bool dryRun,
        bool quiet,
        CancellationToken cancellationToken)
    {
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

        var mode = string.Equals(subcommand, "check", StringComparison.Ordinal)
            ? ContainerLinkRepairMode.Check
            : dryRun
                ? ContainerLinkRepairMode.DryRun
                : ContainerLinkRepairMode.Fix;

        return await containerLinkRepairService
            .RunAsync(containerName, mode, quiet, cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task<int> RunUpdateAsync(
        bool dryRun,
        bool stopContainers,
        bool limaRecreate,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai update [--dry-run] [--stop-containers] [--force] [--lima-recreate]").ConfigureAwait(false);
            return 0;
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

        var refreshCode = await RunRefreshAsync(rebuild: true, showHelp: false, cancellationToken).ConfigureAwait(false);
        if (refreshCode != 0)
        {
            return refreshCode;
        }

        var doctorCode = await runDoctorAsync(false, false, false, cancellationToken).ConfigureAwait(false);
        if (doctorCode != 0)
        {
            await stderr.WriteLineAsync("Update completed with validation warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Update complete.").ConfigureAwait(false);
        return 0;
    }

    public async Task<int> RunRefreshAsync(bool rebuild, bool showHelp, CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai refresh [--rebuild] [--verbose]").ConfigureAwait(false);
            return 0;
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

        if (!rebuild)
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

    public async Task<int> RunUninstallAsync(
        bool dryRun,
        bool removeContainers,
        bool removeVolumes,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai uninstall [--dry-run] [--containers] [--volumes] [--force]").ConfigureAwait(false);
            return 0;
        }

        await RemoveShellIntegrationAsync(dryRun, cancellationToken).ConfigureAwait(false);

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

    private async Task RemoveShellIntegrationAsync(bool dryRun, CancellationToken cancellationToken)
    {
        var homeDirectory = ResolveHomeDirectory();
        var profileScriptPath = ShellProfileIntegration.GetProfileScriptPath(homeDirectory);
        if (dryRun)
        {
            if (File.Exists(profileScriptPath))
            {
                await stdout.WriteLineAsync($"Would remove shell profile script: {profileScriptPath}").ConfigureAwait(false);
            }
        }
        else if (await ShellProfileIntegration.RemoveProfileScriptAsync(homeDirectory, cancellationToken).ConfigureAwait(false))
        {
            await stdout.WriteLineAsync($"Removed shell profile script: {profileScriptPath}").ConfigureAwait(false);
        }

        foreach (var shellProfilePath in ShellProfileIntegration.GetCandidateShellProfilePaths(homeDirectory, Environment.GetEnvironmentVariable("SHELL")))
        {
            if (!File.Exists(shellProfilePath))
            {
                continue;
            }

            var existing = await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false);
            if (!ShellProfileIntegration.HasHookBlock(existing))
            {
                continue;
            }

            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove shell integration from: {shellProfilePath}").ConfigureAwait(false);
                continue;
            }

            if (await ShellProfileIntegration.RemoveHookFromShellProfileAsync(shellProfilePath, cancellationToken).ConfigureAwait(false))
            {
                await stdout.WriteLineAsync($"Removed shell integration from: {shellProfilePath}").ConfigureAwait(false);
            }
        }
    }
}
