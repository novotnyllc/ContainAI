namespace ContainAI.Cli.Host;

internal sealed partial class CaiStopOperations
{
    private async Task<List<(string Context, string Container)>?> ResolveStopTargetsAsync(
        string? containerName,
        bool stopAll,
        CancellationToken cancellationToken)
    {
        var targets = new List<(string Context, string Container)>();
        if (!string.IsNullOrWhiteSpace(containerName))
        {
            var contexts = await FindContainerContextsAsync(containerName, cancellationToken).ConfigureAwait(false);
            if (!await TryAddSingleTargetAsync(contexts, containerName).ConfigureAwait(false))
            {
                return null;
            }

            targets.Add((contexts[0], containerName));
            return targets;
        }

        if (stopAll)
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

            return targets;
        }

        var workspace = Path.GetFullPath(Directory.GetCurrentDirectory());
        var workspaceContainer = await ResolveWorkspaceContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(workspaceContainer))
        {
            await stderr.WriteLineAsync("Usage: cai stop --all | --container <name> [--remove]").ConfigureAwait(false);
            return null;
        }

        var workspaceContexts = await FindContainerContextsAsync(workspaceContainer, cancellationToken).ConfigureAwait(false);
        if (!await TryAddSingleTargetAsync(workspaceContexts, workspaceContainer).ConfigureAwait(false))
        {
            return null;
        }

        targets.Add((workspaceContexts[0], workspaceContainer));
        return targets;
    }

    private async Task<bool> TryAddSingleTargetAsync(List<string> contexts, string containerName)
    {
        if (contexts.Count == 0)
        {
            await stderr.WriteLineAsync($"Container not found: {containerName}").ConfigureAwait(false);
            return false;
        }

        if (contexts.Count > 1)
        {
            await stderr.WriteLineAsync($"Container '{containerName}' exists in multiple contexts: {string.Join(", ", contexts)}").ConfigureAwait(false);
            return false;
        }

        return true;
    }
}
