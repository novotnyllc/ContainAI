using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{
    private async Task<int> RunExportCoreAsync(
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

    private async Task<int> RunSyncCoreAsync(CancellationToken cancellationToken)
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

    private async Task<int> RunLinksCoreAsync(
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
}
