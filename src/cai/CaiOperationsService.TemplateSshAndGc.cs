namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{
    private async Task<int> RunStopCoreAsync(
        string? containerName,
        bool stopAll,
        bool remove,
        bool force,
        bool exportFirst,
        CancellationToken cancellationToken)
    {
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
                var exportExitCode = await RunExportCoreAsync(output: null, explicitVolume: null, container: target.Container, workspace: null, cancellationToken).ConfigureAwait(false);
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
}
