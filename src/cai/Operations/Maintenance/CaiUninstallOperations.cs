namespace ContainAI.Cli.Host;

internal sealed class CaiUninstallOperations : CaiRuntimeSupport
{
    public CaiUninstallOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
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

        await RemoveDockerContextsAsync(dryRun, cancellationToken).ConfigureAwait(false);

        if (!removeContainers)
        {
            await stdout.WriteLineAsync("Uninstall complete (contexts cleaned). Use --containers/--volumes for full cleanup.").ConfigureAwait(false);
            return 0;
        }

        var removeResult = await RemoveManagedContainersAndCollectVolumesAsync(dryRun, removeVolumes, cancellationToken).ConfigureAwait(false);
        if (removeResult.ExitCode != 0)
        {
            return 1;
        }

        await RemoveVolumesAsync(removeResult.VolumeNames, dryRun, cancellationToken).ConfigureAwait(false);

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

    private async Task RemoveDockerContextsAsync(bool dryRun, CancellationToken cancellationToken)
    {
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
    }

    private async Task<UninstallContainerRemovalResult> RemoveManagedContainersAndCollectVolumesAsync(
        bool dryRun,
        bool removeVolumes,
        CancellationToken cancellationToken)
    {
        var list = await DockerCaptureAsync(["ps", "-aq", "--filter", "label=containai.managed=true"], cancellationToken).ConfigureAwait(false);
        if (list.ExitCode != 0)
        {
            await stderr.WriteLineAsync(list.StandardError.Trim()).ConfigureAwait(false);
            return new UninstallContainerRemovalResult(1, []);
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

        return new UninstallContainerRemovalResult(0, volumeNames);
    }

    private async Task RemoveVolumesAsync(IReadOnlyCollection<string> volumeNames, bool dryRun, CancellationToken cancellationToken)
    {
        foreach (var volume in volumeNames)
        {
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove volume {volume}").ConfigureAwait(false);
                continue;
            }

            await DockerCaptureAsync(["volume", "rm", volume], cancellationToken).ConfigureAwait(false);
        }
    }

    private readonly record struct UninstallContainerRemovalResult(int ExitCode, HashSet<string> VolumeNames);
}
