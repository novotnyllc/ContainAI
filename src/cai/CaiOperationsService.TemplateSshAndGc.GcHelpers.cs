namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{
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
