namespace ContainAI.Cli.Host;

internal sealed partial class CaiGcOperations
{
    private readonly record struct CaiGcPruneCandidateResult(int ExitCode, List<string> PruneCandidates, int Failures);

    private async Task<CaiGcPruneCandidateResult> CollectContainerPruneCandidatesAsync(TimeSpan minimumAge, CancellationToken cancellationToken)
    {
        var candidates = await DockerCaptureAsync(
            ["ps", "-aq", "--filter", "label=containai.managed=true", "--filter", "status=exited", "--filter", "status=created"],
            cancellationToken).ConfigureAwait(false);

        if (candidates.ExitCode != 0)
        {
            await stderr.WriteLineAsync(candidates.StandardError.Trim()).ConfigureAwait(false);
            return new CaiGcPruneCandidateResult(1, [], 0);
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

            if (string.Equals(inspectFields[0], "running", StringComparison.Ordinal))
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

        return new CaiGcPruneCandidateResult(0, pruneCandidates, failures);
    }

    private async Task<bool> ConfirmContainerPruneAsync(bool dryRun, bool force, int candidateCount)
    {
        if (dryRun || force || candidateCount == 0)
        {
            return true;
        }

        if (Console.IsInputRedirected)
        {
            await stderr.WriteLineAsync("gc requires --force in non-interactive mode.").ConfigureAwait(false);
            return false;
        }

        await stdout.WriteLineAsync($"About to remove {candidateCount} containers. Continue? [y/N]").ConfigureAwait(false);
        var response = (Console.ReadLine() ?? string.Empty).Trim();
        if (!response.Equals("y", StringComparison.OrdinalIgnoreCase) &&
            !response.Equals("yes", StringComparison.OrdinalIgnoreCase))
        {
            await stdout.WriteLineAsync("Aborted.").ConfigureAwait(false);
            return false;
        }

        return true;
    }

    private async Task<int> PruneContainersAsync(IReadOnlyList<string> pruneCandidates, bool dryRun, CancellationToken cancellationToken)
    {
        var failures = 0;
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

        return failures;
    }

    private async Task<int> PruneImagesAsync(bool dryRun, CancellationToken cancellationToken)
    {
        var failures = 0;
        var images = await DockerCaptureAsync(["images", "--format", "{{.Repository}}:{{.Tag}} {{.ID}}"], cancellationToken).ConfigureAwait(false);
        if (images.ExitCode != 0)
        {
            return failures;
        }

        foreach (var line in images.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length != 2)
            {
                continue;
            }

            var reference = parts[0];
            var imageId = parts[1];
            if (!containAiImagePrefixes.Any(prefix => reference.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
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

        return failures;
    }
}
