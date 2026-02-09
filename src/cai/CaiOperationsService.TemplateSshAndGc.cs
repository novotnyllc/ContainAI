using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{

    private async Task<int> RunTemplateUpgradeCoreAsync(
        string? templateName,
        bool dryRun,
        CancellationToken cancellationToken)
    {
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

    private async Task<int> RunSshCleanupCoreAsync(bool dryRun, CancellationToken cancellationToken)
    {
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

    private async Task<int> RunGcCoreAsync(
        bool dryRun,
        bool force,
        bool includeImages,
        string ageValue,
        CancellationToken cancellationToken)
    {
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
}
